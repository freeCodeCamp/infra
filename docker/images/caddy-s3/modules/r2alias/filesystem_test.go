package r2alias

import (
	"context"
	"errors"
	"io"
	"io/fs"
	"strings"
	"testing"
	"time"

	"github.com/caddyserver/caddy/v2/caddyconfig/caddyfile"
)

// newTestR2FS returns an R2FS pre-seeded with config fields and with the
// tests' fetcher slot left open. Tests assign `r.fetcher` to control how
// Open resolves S3 GetObject. No AWS SDK client is constructed.
func newTestR2FS() *R2FS {
	return &R2FS{
		Bucket:   "test-bucket",
		Endpoint: "https://r2.example",
		Region:   "auto",
	}
}

func stubFSFetcher(obj *r2Object, err error) func(context.Context, string) (*r2Object, error) {
	return func(context.Context, string) (*r2Object, error) { return obj, err }
}

// TestR2FS_Open_Success asserts a valid fetcher response yields a readable
// fs.File whose Stat() reports the object's size and ModTime.
func TestR2FS_Open_Success(t *testing.T) {
	t.Parallel()
	body := []byte("<html>V1</html>")
	modTime := time.Date(2026, 4, 18, 12, 0, 0, 0, time.UTC)

	r := newTestR2FS()
	r.fetcher = stubFSFetcher(&r2Object{
		Body:         body,
		Size:         int64(len(body)),
		LastModified: modTime,
		ContentType:  "text/html",
	}, nil)

	f, err := r.Open("site-a.test.camp/deploys/v1/index.html")
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer f.Close()

	info, err := f.Stat()
	if err != nil {
		t.Fatalf("Stat: %v", err)
	}
	if got := info.Size(); got != int64(len(body)) {
		t.Errorf("Size: want %d, got %d", len(body), got)
	}
	if !info.ModTime().Equal(modTime) {
		t.Errorf("ModTime: want %v, got %v", modTime, info.ModTime())
	}
	if info.IsDir() {
		t.Error("IsDir should be false for a regular object")
	}
	if info.Name() != "index.html" {
		t.Errorf("Name: want index.html, got %q", info.Name())
	}

	got, err := io.ReadAll(f)
	if err != nil {
		t.Fatalf("ReadAll: %v", err)
	}
	if string(got) != string(body) {
		t.Errorf("Body: want %q, got %q", body, got)
	}
}

// TestR2FS_Open_NotFound asserts NoSuchKey-equivalent fetcher errors
// surface as fs.ErrNotExist so file_server returns 404.
func TestR2FS_Open_NotFound(t *testing.T) {
	t.Parallel()
	r := newTestR2FS()
	r.fetcher = stubFSFetcher(nil, fs.ErrNotExist)

	_, err := r.Open("site-a.test.camp/deploys/v1/missing.html")
	if err == nil {
		t.Fatal("Open should fail on missing object")
	}
	if !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("error should wrap fs.ErrNotExist, got %v", err)
	}
	var pe *fs.PathError
	if !errors.As(err, &pe) || pe.Op != "open" {
		t.Errorf("expected *fs.PathError with Op=open, got %T %v", err, err)
	}
}

// TestR2FS_Open_5xx asserts an upstream 5xx error is distinguishable from
// fs.ErrNotExist. file_server maps the former to 500/503, the latter to 404.
func TestR2FS_Open_5xx(t *testing.T) {
	t.Parallel()
	upstreamErr := errors.New("r2: upstream 5xx: service unavailable")
	r := newTestR2FS()
	r.fetcher = stubFSFetcher(nil, upstreamErr)

	_, err := r.Open("site-a.test.camp/deploys/v1/index.html")
	if err == nil {
		t.Fatal("Open should propagate upstream error")
	}
	if errors.Is(err, fs.ErrNotExist) {
		t.Errorf("5xx error should NOT match fs.ErrNotExist, got %v", err)
	}
}

// TestR2FS_Open_InvalidPath asserts paths that fail fs.ValidPath are
// rejected with fs.ErrInvalid — protects against `..`, absolute, etc.
func TestR2FS_Open_InvalidPath(t *testing.T) {
	t.Parallel()
	r := newTestR2FS()
	r.fetcher = func(context.Context, string) (*r2Object, error) {
		t.Fatal("fetcher should NOT be called on invalid path")
		return nil, nil
	}

	cases := []string{"/leading-slash", "foo/../bar", "foo//bar"}
	for _, name := range cases {
		name := name
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			_, err := r.Open(name)
			if err == nil {
				t.Fatalf("Open(%q) should fail on invalid path", name)
			}
			if !errors.Is(err, fs.ErrInvalid) {
				t.Errorf("error should wrap fs.ErrInvalid, got %v", err)
			}
		})
	}
}

// TestR2FS_Seeker asserts the opened file implements io.ReadSeeker so
// file_server can honor Range requests via http.ServeContent.
func TestR2FS_Seeker(t *testing.T) {
	t.Parallel()
	body := []byte("abcdefghijklmnopqrstuvwxyz")
	r := newTestR2FS()
	r.fetcher = stubFSFetcher(&r2Object{Body: body, Size: int64(len(body))}, nil)

	f, err := r.Open("alpha.txt")
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer f.Close()

	seeker, ok := f.(io.Seeker)
	if !ok {
		t.Fatal("file does not implement io.Seeker — Range requests would fail")
	}
	pos, err := seeker.Seek(10, io.SeekStart)
	if err != nil {
		t.Fatalf("Seek: %v", err)
	}
	if pos != 10 {
		t.Errorf("Seek pos: want 10, got %d", pos)
	}
	remainder, err := io.ReadAll(f)
	if err != nil {
		t.Fatalf("ReadAll post-seek: %v", err)
	}
	if string(remainder) != "klmnopqrstuvwxyz" {
		t.Errorf("post-seek read: want %q, got %q", "klmnopqrstuvwxyz", remainder)
	}
}

// TestR2FS_UnmarshalCaddyfile_FullBlock asserts the Caddyfile parser
// populates every R2FS config field from a complete directive block.
func TestR2FS_UnmarshalCaddyfile_FullBlock(t *testing.T) {
	t.Parallel()
	const input = `r2 {
		bucket foo
		endpoint https://r2.example
		region auto
		access_key_id kid
		secret_access_key sak
		use_path_style
		max_file_size 50000000
	}`
	d := caddyfile.NewTestDispenser(input)
	r := new(R2FS)
	if err := r.UnmarshalCaddyfile(d); err != nil {
		t.Fatalf("unexpected parse error: %v", err)
	}
	if r.Bucket != "foo" {
		t.Errorf("Bucket: got %q", r.Bucket)
	}
	if r.Endpoint != "https://r2.example" {
		t.Errorf("Endpoint: got %q", r.Endpoint)
	}
	if r.Region != "auto" {
		t.Errorf("Region: got %q", r.Region)
	}
	if r.AccessKeyID != "kid" || r.SecretAccessKey != "sak" {
		t.Errorf("creds: %+v", r)
	}
	if !r.UsePathStyle {
		t.Errorf("UsePathStyle should be true after flag")
	}
	if r.MaxFileSize != 50_000_000 {
		t.Errorf("MaxFileSize: got %d", r.MaxFileSize)
	}
}

// TestR2FS_UnmarshalCaddyfile_UnknownToken asserts typos surface at parse
// time. Matches the r2_alias handler's strictness.
func TestR2FS_UnmarshalCaddyfile_UnknownToken(t *testing.T) {
	t.Parallel()
	const input = `r2 {
		bucket foo
		wat wrong
	}`
	d := caddyfile.NewTestDispenser(input)
	r := new(R2FS)
	err := r.UnmarshalCaddyfile(d)
	if err == nil || !strings.Contains(err.Error(), "unknown caddy.fs.r2 sub-directive") {
		t.Fatalf("expected unknown-directive error, got %v", err)
	}
}

// TestR2FS_CaddyModule_ID asserts the filesystem module registers at the
// documented ID — file_server uses this namespace to resolve `fs <name>`.
func TestR2FS_CaddyModule_ID(t *testing.T) {
	t.Parallel()
	info := R2FS{}.CaddyModule()
	if info.ID != "caddy.fs.r2" {
		t.Fatalf("CaddyModule ID: want caddy.fs.r2, got %s", info.ID)
	}
	if info.New == nil || info.New() == nil {
		t.Fatal("CaddyModule.New must produce a non-nil instance")
	}
}
