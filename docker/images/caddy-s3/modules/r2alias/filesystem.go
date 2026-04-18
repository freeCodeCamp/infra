package r2alias

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"path"
	"strconv"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awshttp "github.com/aws/aws-sdk-go-v2/aws/transport/http"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	s3types "github.com/aws/aws-sdk-go-v2/service/s3/types"
	"github.com/caddyserver/caddy/v2"
	"github.com/caddyserver/caddy/v2/caddyconfig/caddyfile"
	"go.uber.org/zap"
)

// defaultMaxFileSize caps the in-memory buffer for any single object. 100 MiB
// comfortably covers typical static assets (HTML/CSS/JS/images, the few MB
// range). Larger objects return fs.ErrInvalid from Open — ship them out of
// band rather than streaming through a static-serving cluster.
const defaultMaxFileSize int64 = 100 * 1024 * 1024

// R2FS is a Caddy filesystem module (caddy.fs.r2) that serves objects from
// an S3-compatible bucket (Cloudflare R2 in production). Lives in the same
// Go package as R2Alias per RFC D32 (§5.30) — the audit on 2026-04-18
// dropped the third-party caddy-fs-s3 dep after 14-month upstream silence.
//
// After R2Alias (http.handlers.r2_alias) rewrites req.URL.Path to
// /{site}/deploys/{deployID}{origPath}, file_server calls R2FS.Open on
// that path; the object comes straight from R2.
type R2FS struct {
	Bucket          string `json:"bucket"`
	Endpoint        string `json:"endpoint"`
	Region          string `json:"region"`
	AccessKeyID     string `json:"access_key_id,omitempty"`
	SecretAccessKey string `json:"secret_access_key,omitempty"`
	UsePathStyle    bool   `json:"use_path_style,omitempty"`
	MaxFileSize     int64  `json:"max_file_size,omitempty"`

	client *s3.Client
	logger *zap.Logger

	// fetcher is the GetObject path invoked by Open. Provision wires it to
	// r.getObject against the real S3 client; tests substitute a stub so the
	// fs behavior can be exercised without AWS plumbing.
	fetcher func(ctx context.Context, key string) (*r2Object, error)
}

// r2Object is the in-memory representation of a fetched R2 object. Body is
// the complete payload (bounded by MaxFileSize); Size and LastModified are
// copied from the GetObject / HeadObject response.
type r2Object struct {
	Body         []byte
	Size         int64
	LastModified time.Time
	ContentType  string
}

func init() {
	caddy.RegisterModule(R2FS{})
}

// CaddyModule returns the filesystem module information.
func (R2FS) CaddyModule() caddy.ModuleInfo {
	return caddy.ModuleInfo{
		ID:  "caddy.fs.r2",
		New: func() caddy.Module { return new(R2FS) },
	}
}

// Provision validates config, constructs the S3 client, and installs the
// default fetcher. Called once at startup.
func (r *R2FS) Provision(ctx caddy.Context) error {
	if r.Bucket == "" {
		return fmt.Errorf("caddy.fs.r2: bucket is required")
	}
	if r.Endpoint == "" {
		return fmt.Errorf("caddy.fs.r2: endpoint is required")
	}
	if r.Region == "" {
		r.Region = "auto"
	}
	if r.MaxFileSize <= 0 {
		r.MaxFileSize = defaultMaxFileSize
	}

	awsCfg, err := config.LoadDefaultConfig(ctx,
		config.WithRegion(r.Region),
		config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(
			r.AccessKeyID, r.SecretAccessKey, "",
		)),
	)
	if err != nil {
		return fmt.Errorf("caddy.fs.r2: load aws config: %w", err)
	}
	r.client = s3.NewFromConfig(awsCfg, func(o *s3.Options) {
		o.BaseEndpoint = aws.String(r.Endpoint)
		// R2 requires path-style addressing and S3Mock supports it. The
		// `use_path_style` Caddyfile flag is accepted for forward-compat but
		// we always enable it — the bucket-in-hostname alternative would
		// break the module's primary target (R2).
		o.UsePathStyle = true
	})
	r.logger = ctx.Logger()
	if r.fetcher == nil {
		r.fetcher = r.getObject
	}
	return nil
}

// UnmarshalCaddyfile parses the R2FS directive block. Every sub-directive
// takes a single argument EXCEPT `use_path_style`, which is a no-argument
// flag. Unknown tokens surface as parse errors.
//
// Grammar:
//
//	r2 {
//	    bucket <str>
//	    endpoint <str>
//	    region <str>
//	    access_key_id <str>
//	    secret_access_key <str>
//	    use_path_style
//	    max_file_size <int-bytes>
//	}
func (r *R2FS) UnmarshalCaddyfile(d *caddyfile.Dispenser) error {
	for d.Next() {
		if d.NextArg() {
			return d.ArgErr()
		}
		for d.NextBlock(0) {
			switch d.Val() {
			case "bucket":
				if !d.NextArg() {
					return d.ArgErr()
				}
				r.Bucket = d.Val()
			case "endpoint":
				if !d.NextArg() {
					return d.ArgErr()
				}
				r.Endpoint = d.Val()
			case "region":
				if !d.NextArg() {
					return d.ArgErr()
				}
				r.Region = d.Val()
			case "access_key_id":
				if !d.NextArg() {
					return d.ArgErr()
				}
				r.AccessKeyID = d.Val()
			case "secret_access_key":
				if !d.NextArg() {
					return d.ArgErr()
				}
				r.SecretAccessKey = d.Val()
			case "use_path_style":
				r.UsePathStyle = true
			case "max_file_size":
				if !d.NextArg() {
					return d.ArgErr()
				}
				n, err := strconv.ParseInt(d.Val(), 10, 64)
				if err != nil {
					return d.Errf("max_file_size: %v", err)
				}
				r.MaxFileSize = n
			default:
				return d.Errf("unknown caddy.fs.r2 sub-directive: %s", d.Val())
			}
		}
	}
	return nil
}

// Open implements fs.FS. Invalid paths (absolute, traversal, double-slash)
// return fs.ErrInvalid; missing objects return fs.ErrNotExist; all other
// errors propagate so file_server can map them to 5xx.
//
// The returned file implements io.ReadSeeker + io.ReaderAt so file_server
// (via http.ServeContent) can honor Range requests.
func (r *R2FS) Open(name string) (fs.File, error) {
	if !fs.ValidPath(name) {
		return nil, &fs.PathError{Op: "open", Path: name, Err: fs.ErrInvalid}
	}
	obj, err := r.fetcher(context.Background(), name)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return nil, &fs.PathError{Op: "open", Path: name, Err: fs.ErrNotExist}
		}
		return nil, &fs.PathError{Op: "open", Path: name, Err: err}
	}
	return &r2File{
		reader: bytes.NewReader(obj.Body),
		info: &r2FileInfo{
			name:    path.Base(name),
			size:    obj.Size,
			modTime: obj.LastModified,
		},
	}, nil
}

// Stat implements fs.StatFS. Delegates to Open so both paths share one
// fetcher — simpler to test, and static-serving traffic opens the file
// anyway (http.ServeContent calls Stat then reads the body).
func (r *R2FS) Stat(name string) (fs.FileInfo, error) {
	f, err := r.Open(name)
	if err != nil {
		// Rewrite PathError Op from "open" to "stat" for clarity.
		var pe *fs.PathError
		if errors.As(err, &pe) {
			pe.Op = "stat"
		}
		return nil, err
	}
	defer func() { _ = f.Close() }()
	return f.Stat()
}

// getObject is the default fetcher. Reads an object from R2 via GetObject,
// bounds the body by MaxFileSize, and classifies upstream errors. NoSuchKey
// is mapped to fs.ErrNotExist so callers can use errors.Is.
func (r *R2FS) getObject(ctx context.Context, key string) (*r2Object, error) {
	out, err := r.client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(r.Bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		if isNoSuchKey(err) {
			return nil, fmt.Errorf("caddy.fs.r2: %w", fs.ErrNotExist)
		}
		var respErr *awshttp.ResponseError
		if errors.As(err, &respErr) && respErr.HTTPStatusCode() >= 500 {
			return nil, fmt.Errorf("caddy.fs.r2: upstream 5xx: %w", err)
		}
		return nil, fmt.Errorf("caddy.fs.r2: GetObject %s: %w", key, err)
	}
	defer func() { _ = out.Body.Close() }()

	if out.ContentLength != nil && *out.ContentLength > r.MaxFileSize {
		return nil, fmt.Errorf("caddy.fs.r2: object %s size %d exceeds max_file_size %d",
			key, *out.ContentLength, r.MaxFileSize)
	}

	body, readErr := io.ReadAll(io.LimitReader(out.Body, r.MaxFileSize))
	if readErr != nil {
		return nil, fmt.Errorf("caddy.fs.r2: read body %s: %w", key, readErr)
	}

	var modTime time.Time
	if out.LastModified != nil {
		modTime = *out.LastModified
	}
	var ct string
	if out.ContentType != nil {
		ct = *out.ContentType
	}
	return &r2Object{
		Body:         body,
		Size:         int64(len(body)),
		LastModified: modTime,
		ContentType:  ct,
	}, nil
}

// isNoSuchKey classifies an error as a "not found" signal from R2/S3.
// Matches both the typed s3types.NoSuchKey response and a generic 404
// response wrapped in awshttp.ResponseError (R2 occasionally returns the
// latter instead of a typed error).
func isNoSuchKey(err error) bool {
	var nsk *s3types.NoSuchKey
	if errors.As(err, &nsk) {
		return true
	}
	var respErr *awshttp.ResponseError
	if errors.As(err, &respErr) && respErr.HTTPStatusCode() == 404 {
		return true
	}
	return false
}

// --- fs.File + fs.FileInfo implementations --------------------------------

// r2File is the fs.File returned by R2FS.Open. The body is in-memory so the
// reader is a bytes.Reader — satisfies io.ReadSeeker + io.ReaderAt for
// http.ServeContent's Range handling.
type r2File struct {
	reader *bytes.Reader
	info   *r2FileInfo
}

func (f *r2File) Stat() (fs.FileInfo, error)                   { return f.info, nil }
func (f *r2File) Read(b []byte) (int, error)                   { return f.reader.Read(b) }
func (f *r2File) Seek(offset int64, whence int) (int64, error) { return f.reader.Seek(offset, whence) }
func (f *r2File) ReadAt(p []byte, off int64) (int, error)      { return f.reader.ReadAt(p, off) }
func (f *r2File) Close() error                                 { return nil }

// r2FileInfo is the fs.FileInfo for a single R2 object. Static objects are
// read-only (Mode 0444) and never directories.
type r2FileInfo struct {
	name    string
	size    int64
	modTime time.Time
}

func (fi *r2FileInfo) Name() string       { return fi.name }
func (fi *r2FileInfo) Size() int64        { return fi.size }
func (fi *r2FileInfo) Mode() fs.FileMode  { return 0o444 }
func (fi *r2FileInfo) ModTime() time.Time { return fi.modTime }
func (fi *r2FileInfo) IsDir() bool        { return false }
func (fi *r2FileInfo) Sys() any           { return nil }

// Interface guards.
var (
	_ fs.StatFS             = (*R2FS)(nil)
	_ caddy.Provisioner     = (*R2FS)(nil)
	_ caddyfile.Unmarshaler = (*R2FS)(nil)
	_ io.ReadSeeker         = (*r2File)(nil)
	_ io.ReaderAt           = (*r2File)(nil)
	_ fs.File               = (*r2File)(nil)
	_ fs.FileInfo           = (*r2FileInfo)(nil)
)
