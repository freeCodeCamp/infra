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

// defaultMaxFileSize caps the in-memory buffer for any single object.
// Larger objects return fs.ErrInvalid from Open — ship them out of band
// rather than streaming through a static-serving cluster.
const defaultMaxFileSize int64 = 100 * 1024 * 1024

// opTimeout bounds every S3 round-trip from Open. fs.FS has no context
// parameter, so the ceiling is enforced here rather than by the caller.
const opTimeout = 30 * time.Second

// indexFile is the only filename probed when synthesizing virtual dirs. S3
// has no directory concept, but static-site deploys always ship index.html,
// so one HeadObject against that key fully decides the directory question.
const indexFile = "index.html"

// R2FS is a Caddy filesystem module (caddy.fs.r2) that serves objects from
// an S3-compatible bucket.
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

	// fetcher is the GetObject path. Provision wires it to r.getObject;
	// tests swap in a stub so Open/Stat run without an S3 client.
	fetcher func(ctx context.Context, key string) (*r2Object, error)

	header func(ctx context.Context, key string) (*r2Object, error)

	// indexProbe reports whether a directory's index.html exists. Provision
	// wires it to r.hasIndex, which issues a HeadObject — matching the Caddy
	// key's GetObject-only IAM scope (RFC §4.2.4). Backs Open's virtual-
	// directory synthesis so file_server can resolve directory paths.
	indexProbe func(ctx context.Context, dirPath string) (bool, error)
}

type r2Object struct {
	Body         []byte
	Size         int64
	LastModified time.Time
	ContentType  string
}

func init() {
	caddy.RegisterModule(R2FS{})
}

func (R2FS) CaddyModule() caddy.ModuleInfo {
	return caddy.ModuleInfo{
		ID:  "caddy.fs.r2",
		New: func() caddy.Module { return new(R2FS) },
	}
}

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
		// R2 requires path-style; bucket-in-hostname would break the target.
		o.UsePathStyle = true
	})
	r.logger = ctx.Logger()
	if r.fetcher == nil {
		r.fetcher = r.getObject
	}
	if r.header == nil {
		r.header = r.headObject
	}
	if r.indexProbe == nil {
		r.indexProbe = r.hasIndex
	}
	return nil
}

// UnmarshalCaddyfile parses:
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

// Open returns a file whose body implements io.ReadSeeker + io.ReaderAt so
// http.ServeContent can honor Range requests. When the object is missing but
// an index.html exists beneath the path, Open returns a synthetic directory
// entry so file_server can locate that index.
func (r *R2FS) Open(name string) (fs.File, error) {
	if !fs.ValidPath(name) {
		return nil, &fs.PathError{Op: "open", Path: name, Err: fs.ErrInvalid}
	}
	ctx, cancel := context.WithTimeout(context.Background(), opTimeout)
	defer cancel()

	head, err := r.header(ctx, name)
	if err == nil {
		if head.Size > r.MaxFileSize {
			r.logger.Warn("r2 object exceeds max_file_size",
				zap.String("path", name), zap.Int64("size", head.Size))
			return nil, &fs.PathError{Op: "open", Path: name, Err: fs.ErrInvalid}
		}
		return &r2File{
			info: &r2FileInfo{
				name:    path.Base(name),
				size:    head.Size,
				modTime: head.LastModified,
			},
			load: func() ([]byte, error) {
				loadCtx, loadCancel := context.WithTimeout(context.Background(), opTimeout)
				defer loadCancel()
				obj, ferr := r.fetcher(loadCtx, name)
				if ferr != nil {
					r.logger.Error("r2 body fetch failed",
						zap.String("path", name), zap.Error(ferr))
					return nil, ferr
				}
				return obj.Body, nil
			},
		}, nil
	}
	if !errors.Is(err, fs.ErrNotExist) {
		return nil, &fs.PathError{Op: "open", Path: name, Err: err}
	}

	if r.indexProbe != nil {
		has, probeErr := r.indexProbe(ctx, name)
		if probeErr != nil {
			r.logger.Warn("r2 index probe failed",
				zap.String("path", name), zap.Error(probeErr))
			return nil, &fs.PathError{Op: "open", Path: name, Err: probeErr}
		}
		if has {
			r.logger.Debug("r2 virtual directory", zap.String("path", name))
			return &r2File{
				info: &r2FileInfo{
					name:  path.Base(name),
					isDir: true,
				},
			}, nil
		}
	}
	return nil, &fs.PathError{Op: "open", Path: name, Err: fs.ErrNotExist}
}

// Unreachable through file_server: caddy v2.11.3 registers every filesystem in
// internal/filesystems.wrapperFs, which embeds only fs.FS and hides fs.StatFS.
func (r *R2FS) Stat(name string) (fs.FileInfo, error) {
	if !fs.ValidPath(name) {
		return nil, &fs.PathError{Op: "stat", Path: name, Err: fs.ErrInvalid}
	}
	ctx, cancel := context.WithTimeout(context.Background(), opTimeout)
	defer cancel()

	obj, err := r.header(ctx, name)
	if err == nil {
		return &r2FileInfo{
			name:    path.Base(name),
			size:    obj.Size,
			modTime: obj.LastModified,
		}, nil
	}
	if !errors.Is(err, fs.ErrNotExist) {
		return nil, &fs.PathError{Op: "stat", Path: name, Err: err}
	}

	if r.indexProbe != nil {
		has, probeErr := r.indexProbe(ctx, name)
		if probeErr != nil {
			r.logger.Warn("r2 index probe failed",
				zap.String("path", name), zap.Error(probeErr))
			return nil, &fs.PathError{Op: "stat", Path: name, Err: probeErr}
		}
		if has {
			return &r2FileInfo{name: path.Base(name), isDir: true}, nil
		}
	}
	return nil, &fs.PathError{Op: "stat", Path: name, Err: fs.ErrNotExist}
}

func (r *R2FS) headObject(ctx context.Context, key string) (*r2Object, error) {
	out, err := r.client.HeadObject(ctx, &s3.HeadObjectInput{
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
		return nil, fmt.Errorf("caddy.fs.r2: HeadObject %s: %w", key, err)
	}

	obj := &r2Object{}
	if out.ContentLength != nil {
		obj.Size = *out.ContentLength
	}
	if out.LastModified != nil {
		obj.LastModified = *out.LastModified
	}
	if out.ContentType != nil {
		obj.ContentType = *out.ContentType
	}
	return obj, nil
}

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

// hasIndex reports whether a directory's index.html exists under dirPath by
// issuing a HeadObject. HeadObject only requires the s3:GetObject permission
// — matching the scope granted to the Caddy read-only key (RFC §4.2.4) —
// where ListObjectsV2 would need s3:ListBucket, which is not granted.
func (r *R2FS) hasIndex(ctx context.Context, dirPath string) (bool, error) {
	_, err := r.headObject(ctx, dirPath+"/"+indexFile)
	if errors.Is(err, fs.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return true, nil
}

// isNoSuchKey matches the typed s3types.NoSuchKey AND a generic 404 wrapped
// in awshttp.ResponseError (R2 sometimes returns the latter).
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

type r2File struct {
	info   *r2FileInfo
	load   func() ([]byte, error)
	reader *bytes.Reader
	offset int64
}

func (f *r2File) body() (*bytes.Reader, error) {
	if f.reader != nil {
		return f.reader, nil
	}
	var raw []byte
	if f.load != nil {
		var err error
		if raw, err = f.load(); err != nil {
			return nil, err
		}
	}
	f.reader = bytes.NewReader(raw)
	if _, err := f.reader.Seek(f.offset, io.SeekStart); err != nil {
		return nil, err
	}
	return f.reader, nil
}

func (f *r2File) Stat() (fs.FileInfo, error) { return f.info, nil }

func (f *r2File) Read(p []byte) (int, error) {
	reader, err := f.body()
	if err != nil {
		return 0, err
	}
	n, readErr := reader.Read(p)
	f.offset += int64(n)
	return n, readErr
}

func (f *r2File) Seek(offset int64, whence int) (int64, error) {
	if f.reader != nil {
		pos, err := f.reader.Seek(offset, whence)
		f.offset = pos
		return pos, err
	}

	var abs int64
	switch whence {
	case io.SeekStart:
		abs = offset
	case io.SeekCurrent:
		abs = f.offset + offset
	case io.SeekEnd:
		abs = f.info.size + offset
	default:
		return 0, fs.ErrInvalid
	}
	if abs < 0 {
		return 0, fs.ErrInvalid
	}
	f.offset = abs
	return abs, nil
}

func (f *r2File) ReadAt(p []byte, off int64) (int, error) {
	reader, err := f.body()
	if err != nil {
		return 0, err
	}
	return reader.ReadAt(p, off)
}

func (f *r2File) Close() error { return nil }

type r2FileInfo struct {
	name    string
	size    int64
	modTime time.Time
	isDir   bool
}

func (fi *r2FileInfo) Name() string { return fi.name }
func (fi *r2FileInfo) Size() int64  { return fi.size }
func (fi *r2FileInfo) Mode() fs.FileMode {
	if fi.isDir {
		return fs.ModeDir | 0o555
	}
	return 0o444
}
func (fi *r2FileInfo) ModTime() time.Time { return fi.modTime }
func (fi *r2FileInfo) IsDir() bool        { return fi.isDir }
func (fi *r2FileInfo) Sys() any           { return nil }

var (
	_ fs.StatFS             = (*R2FS)(nil)
	_ caddy.Provisioner     = (*R2FS)(nil)
	_ caddyfile.Unmarshaler = (*R2FS)(nil)
	_ io.ReadSeeker         = (*r2File)(nil)
	_ io.ReaderAt           = (*r2File)(nil)
	_ fs.File               = (*r2File)(nil)
	_ fs.FileInfo           = (*r2FileInfo)(nil)
)
