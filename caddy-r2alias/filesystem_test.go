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
	"go.uber.org/zap"
)

// Tests assign r.fetcher to control how Open resolves S3 GetObject. No AWS
// SDK client is constructed.
func newTestR2FS() *R2FS {
	r := &R2FS{
		Bucket:      "test-bucket",
		Endpoint:    "https://r2.example",
		Region:      "auto",
		MaxFileSize: defaultMaxFileSize,
		logger:      zap.NewNop(),
	}
	r.header = func(ctx context.Context, key string) (*r2Object, error) {
		return r.fetcher(ctx, key)
	}
	return r
}

func stubFSFetcher(obj *r2Object, err error) func(context.Context, string) (*r2Object, error) {
	return func(context.Context, string) (*r2Object, error) { return obj, err }
}

func stubIndexProbe(has bool, err error) func(context.Context, string) (bool, error) {
	return func(context.Context, string) (bool, error) { return has, err }
}

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

// file_server maps fs.ErrNotExist to 404, so NoSuchKey must surface that.
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

// file_server maps fs.ErrNotExist to 404 and other errors to 5xx, so the
// two must be distinguishable.
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

// fs.ValidPath rejects absolute paths, traversal, and double-slash.
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

// http.ServeContent needs io.ReadSeeker for Range requests.
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
	if r.UsePathStyle == nil || !*r.UsePathStyle {
		t.Errorf("UsePathStyle should be true after flag")
	}
	if r.MaxFileSize != 50_000_000 {
		t.Errorf("MaxFileSize: got %d", r.MaxFileSize)
	}
}

func TestR2FS_UnmarshalCaddyfile_MissingArgument(t *testing.T) {
	t.Parallel()
	for _, directive := range []string{
		"bucket", "endpoint", "region", "access_key_id", "secret_access_key",
		"max_file_size", "max_in_flight_bytes",
	} {
		t.Run(directive, func(t *testing.T) {
			t.Parallel()
			d := caddyfile.NewTestDispenser("r2 {\n\t" + directive + "\n}")
			if err := new(R2FS).UnmarshalCaddyfile(d); err == nil {
				t.Fatalf("%s with no argument must not parse", directive)
			}
		})
	}
}

func TestR2FS_UnmarshalCaddyfile_RejectsAnInlineArgument(t *testing.T) {
	t.Parallel()
	d := caddyfile.NewTestDispenser("r2 unexpected {\n\tbucket foo\n}")
	if err := new(R2FS).UnmarshalCaddyfile(d); err == nil {
		t.Fatal("r2 takes no inline argument")
	}
}

func TestR2FS_UnmarshalCaddyfile_RejectsANonNumericMaxFileSize(t *testing.T) {
	t.Parallel()
	d := caddyfile.NewTestDispenser("r2 {\n\tmax_file_size lots\n}")
	err := new(R2FS).UnmarshalCaddyfile(d)
	if err == nil || !strings.Contains(err.Error(), "max_file_size") {
		t.Fatalf("expected a max_file_size parse error, got %v", err)
	}
}

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

// file_server relies on IsDir() to discover index.html. S3 has no directories,
// so Open/Stat synthesize one when the GetObject miss is backed by an
// index.html under the path.
func TestR2FS_Open_VirtualDirectory(t *testing.T) {
	t.Parallel()
	r := newTestR2FS()
	r.fetcher = stubFSFetcher(nil, fs.ErrNotExist)
	r.indexProbe = stubIndexProbe(true, nil)

	f, err := r.Open("site-a.test.camp/deploys/v1")
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer func() { _ = f.Close() }()

	info, err := f.Stat()
	if err != nil {
		t.Fatalf("Stat: %v", err)
	}
	if !info.IsDir() {
		t.Error("virtual directory should report IsDir=true")
	}
	if info.Name() != "v1" {
		t.Errorf("Name: want v1, got %q", info.Name())
	}
	if info.Mode()&fs.ModeDir == 0 {
		t.Errorf("Mode should include ModeDir, got %v", info.Mode())
	}
}

// A miss with no index.html under the path must still surface as ErrNotExist
// so file_server returns a 404 instead of an empty-body 200.
func TestR2FS_Open_NotFound_NoIndex(t *testing.T) {
	t.Parallel()
	r := newTestR2FS()
	r.fetcher = stubFSFetcher(nil, fs.ErrNotExist)
	r.indexProbe = stubIndexProbe(false, nil)

	_, err := r.Open("site-a.test.camp/deploys/v1/missing")
	if err == nil {
		t.Fatal("Open should fail when neither object nor index.html exists")
	}
	if !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("error should wrap fs.ErrNotExist, got %v", err)
	}
}

func TestR2FS_Open_NotFound_ProbesDottedDirectory(t *testing.T) {
	t.Parallel()
	r := newTestR2FS()
	r.fetcher = stubFSFetcher(nil, fs.ErrNotExist)
	probed := ""
	r.indexProbe = func(_ context.Context, dir string) (bool, error) {
		probed = dir
		return true, nil
	}

	f, err := r.Open("site-a.test.camp/deploys/v1/assets.min")
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer func() { _ = f.Close() }()

	info, err := f.Stat()
	if err != nil {
		t.Fatalf("Stat: %v", err)
	}
	if !info.IsDir() {
		t.Error("a dotted directory must resolve to a virtual directory")
	}
	if probed != "site-a.test.camp/deploys/v1/assets.min" {
		t.Errorf("probe path: got %q", probed)
	}
}

func TestR2FS_Open_RejectsOversizeObject(t *testing.T) {
	t.Parallel()
	r := newTestR2FS()
	r.MaxFileSize = 1024
	r.header = stubFSFetcher(&r2Object{Size: 4096}, nil)
	r.fetcher = func(context.Context, string) (*r2Object, error) {
		t.Fatal("an oversize object must be rejected before its body is fetched")
		return nil, nil
	}

	if _, err := r.Open("site-a.test.camp/deploys/v1/big.bin"); !errors.Is(err, fs.ErrInvalid) {
		t.Fatalf("error should wrap fs.ErrInvalid, got %v", err)
	}
}

func TestR2FS_Open_UpstreamErrorIsNotAPathError(t *testing.T) {
	t.Parallel()
	r := newTestR2FS()
	r.header = stubFSFetcher(nil, errors.New("caddy.fs.r2: upstream 5xx: service unavailable"))

	_, err := r.Open("site-a.test.camp/deploys/v1/index.html")
	if err == nil {
		t.Fatal("Open should fail on an upstream error")
	}
	var pe *fs.PathError
	if errors.As(err, &pe) {
		t.Fatalf("caddy maps any *fs.PathError to 400 (staticfiles.go mapDirOpenError), got %T", err)
	}
	if errors.Is(err, fs.ErrInvalid) || errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("an upstream error must not read as invalid or missing, got %v", err)
	}
}

func TestR2FS_Open_SeekSurfacesTheBodyFetchFailure(t *testing.T) {
	t.Parallel()
	fetchErr := errors.New("caddy.fs.r2: upstream 5xx: GetObject failed")
	r := newTestR2FS()
	r.header = stubFSFetcher(&r2Object{Size: 4096}, nil)
	r.fetcher = stubFSFetcher(nil, fetchErr)

	f, err := r.Open("site-a.test.camp/deploys/v1/index.html")
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer func() { _ = f.Close() }()

	if _, seekErr := f.(io.Seeker).Seek(0, io.SeekEnd); !errors.Is(seekErr, fetchErr) {
		t.Fatalf("Seek must surface the fetch failure before ServeContent commits the header, got %v", seekErr)
	}
}

func TestR2FS_Open_ReadSurfacesTheBodyFetchFailure(t *testing.T) {
	t.Parallel()
	fetchErr := errors.New("caddy.fs.r2: upstream 5xx: GetObject failed")
	r := newTestR2FS()
	r.header = stubFSFetcher(&r2Object{Size: 4096}, nil)
	r.fetcher = stubFSFetcher(nil, fetchErr)

	f, err := r.Open("site-a.test.camp/deploys/v1/index.html")
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer func() { _ = f.Close() }()

	if _, readErr := f.Read(make([]byte, 4)); !errors.Is(readErr, fetchErr) {
		t.Fatalf("Read must surface the fetch failure, got %v", readErr)
	}
	if _, readErr := f.(io.ReaderAt).ReadAt(make([]byte, 4), 0); !errors.Is(readErr, fetchErr) {
		t.Fatalf("ReadAt must surface the fetch failure, got %v", readErr)
	}
}

func TestR2FS_Open_IndexProbeFailureIsNotAPathError(t *testing.T) {
	t.Parallel()
	r := newTestR2FS()
	r.header = stubFSFetcher(nil, fs.ErrNotExist)
	r.indexProbe = stubIndexProbe(false, errors.New("caddy.fs.r2: upstream 5xx"))

	_, err := r.Open("site-a.test.camp/deploys/v1")
	if err == nil {
		t.Fatal("a failed index probe must fail Open")
	}
	var pe *fs.PathError
	if errors.As(err, &pe) {
		t.Fatalf("caddy maps any *fs.PathError to 400, got %T", err)
	}
	if errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("a failed probe must not read as a definite miss, got %v", err)
	}
}

func TestR2FS_FileInfo_ModeAndSys(t *testing.T) {
	t.Parallel()
	file := &r2FileInfo{name: "index.html", size: 3}
	if file.Mode() != 0o444 {
		t.Errorf("file mode: want 0444, got %v", file.Mode())
	}
	if file.Sys() != nil {
		t.Errorf("Sys should carry nothing, got %v", file.Sys())
	}

	dir := &r2FileInfo{name: "v1", isDir: true}
	if dir.Mode()&fs.ModeDir == 0 {
		t.Errorf("directory mode should include ModeDir, got %v", dir.Mode())
	}
}

func TestR2FS_Stat_InvalidPath(t *testing.T) {
	t.Parallel()
	r := newTestR2FS()
	r.header = func(context.Context, string) (*r2Object, error) {
		t.Fatal("header should NOT be called on an invalid path")
		return nil, nil
	}

	if _, err := r.Stat("/leading-slash"); !errors.Is(err, fs.ErrInvalid) {
		t.Fatalf("error should wrap fs.ErrInvalid, got %v", err)
	}
}

func TestR2FS_Stat_UpstreamErrorPropagates(t *testing.T) {
	t.Parallel()
	r := newTestR2FS()
	r.header = stubFSFetcher(nil, errors.New("caddy.fs.r2: upstream 5xx"))

	_, err := r.Stat("site-a.test.camp/deploys/v1/index.html")
	if err == nil {
		t.Fatal("Stat should propagate an upstream error")
	}
	if errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("an upstream error must not read as missing, got %v", err)
	}
}

func TestR2FS_Stat_ProbeFailurePropagates(t *testing.T) {
	t.Parallel()
	r := newTestR2FS()
	r.header = stubFSFetcher(nil, fs.ErrNotExist)
	r.indexProbe = stubIndexProbe(false, errors.New("caddy.fs.r2: upstream 5xx"))

	if _, err := r.Stat("site-a.test.camp/deploys/v1"); err == nil {
		t.Fatal("Stat should propagate a failed index probe")
	}
}

func TestR2FS_Stat_NoIndexIsNotExist(t *testing.T) {
	t.Parallel()
	r := newTestR2FS()
	r.header = stubFSFetcher(nil, fs.ErrNotExist)
	r.indexProbe = stubIndexProbe(false, nil)

	if _, err := r.Stat("site-a.test.camp/deploys/v1/missing"); !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("error should wrap fs.ErrNotExist, got %v", err)
	}
}

func TestR2FS_Stat_UsesHeadNotGet(t *testing.T) {
	t.Parallel()
	r := newTestR2FS()
	r.fetcher = func(context.Context, string) (*r2Object, error) {
		t.Fatal("Stat must not download a body")
		return nil, nil
	}
	r.header = stubFSFetcher(&r2Object{Size: 12}, nil)

	info, err := r.Stat("site-a.test.camp/deploys/v1/index.html")
	if err != nil {
		t.Fatalf("Stat: %v", err)
	}
	if info.Size() != 12 {
		t.Errorf("size: want 12, got %d", info.Size())
	}
	if info.IsDir() {
		t.Error("an object Stat must not report IsDir")
	}
}

func TestR2FS_Stat_VirtualDirectory(t *testing.T) {
	t.Parallel()
	r := newTestR2FS()
	r.header = stubFSFetcher(nil, fs.ErrNotExist)
	r.indexProbe = stubIndexProbe(true, nil)

	info, err := r.Stat("site-a.test.camp/deploys/v1")
	if err != nil {
		t.Fatalf("Stat: %v", err)
	}
	if !info.IsDir() {
		t.Error("virtual directory Stat should report IsDir=true")
	}
}

func TestR2FS_Open_SeekSizeMatchesTheDeliveredBody(t *testing.T) {
	t.Parallel()
	body := []byte("SHORT-BODY")
	r := newTestR2FS()
	r.header = stubFSFetcher(&r2Object{Size: 5000}, nil)
	r.fetcher = stubFSFetcher(&r2Object{Body: body, Size: 5000}, nil)

	f, err := r.Open("site-a.test.camp/deploys/v1/index.html")
	if err != nil {
		t.Fatalf("Open: unexpected error: %v", err)
	}
	defer func() { _ = f.Close() }()

	size, err := f.(io.Seeker).Seek(0, io.SeekEnd)
	if err != nil {
		t.Fatalf("Seek: unexpected error: %v", err)
	}
	if size != int64(len(body)) {
		t.Errorf("Seek(0, SeekEnd): want %d, got %d", len(body), size)
	}

	if _, err := f.(io.Seeker).Seek(0, io.SeekStart); err != nil {
		t.Fatalf("Seek to start: %v", err)
	}
	got, err := io.ReadAll(f)
	if err != nil {
		t.Fatalf("ReadAll: %v", err)
	}
	if string(got) != string(body) {
		t.Errorf("body: want %q, got %q", body, got)
	}
}

func TestR2FS_Open_ReadAtServesARange(t *testing.T) {
	t.Parallel()
	r := newTestR2FS()
	r.fetcher = stubFSFetcher(&r2Object{Body: []byte("abcdefghij")}, nil)

	f, err := r.Open("alpha.txt")
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer func() { _ = f.Close() }()

	buf := make([]byte, 3)
	if _, err := f.(io.ReaderAt).ReadAt(buf, 4); err != nil {
		t.Fatalf("ReadAt: %v", err)
	}
	if string(buf) != "efg" {
		t.Errorf("ReadAt(4): want %q, got %q", "efg", buf)
	}
}

func TestR2FS_Open_VirtualDirectoryReadsEmpty(t *testing.T) {
	t.Parallel()
	r := newTestR2FS()
	r.fetcher = stubFSFetcher(nil, fs.ErrNotExist)
	r.indexProbe = stubIndexProbe(true, nil)

	f, err := r.Open("site-a.test.camp/deploys/v1")
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer func() { _ = f.Close() }()

	got, err := io.ReadAll(f)
	if err != nil {
		t.Fatalf("ReadAll on a virtual directory: %v", err)
	}
	if len(got) != 0 {
		t.Errorf("a virtual directory must read empty, got %q", got)
	}
}
