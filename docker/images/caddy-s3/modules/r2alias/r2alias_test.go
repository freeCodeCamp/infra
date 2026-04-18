package r2alias

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/caddyserver/caddy/v2/caddyconfig/caddyfile"
	"github.com/caddyserver/caddy/v2/modules/caddyhttp"
	"go.uber.org/zap"
)

// TestValidate_RequiredFields covers the acceptance criterion:
// "GIVEN Validate() runs with bucket=\"\" or endpoint=\"\" THEN an
// explanatory error is returned".
func TestValidate_RequiredFields(t *testing.T) {
	cases := []struct {
		name    string
		r       R2Alias
		wantErr string
	}{
		{"missing bucket", R2Alias{Endpoint: "https://x"}, "bucket is required"},
		{"missing endpoint", R2Alias{Bucket: "b"}, "endpoint is required"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			err := c.r.Validate()
			if err == nil {
				t.Fatalf("expected error containing %q, got nil", c.wantErr)
			}
			if !strings.Contains(err.Error(), c.wantErr) {
				t.Fatalf("expected error containing %q, got %q", c.wantErr, err.Error())
			}
		})
	}
}

// TestValidate_DefaultsApplied covers the RFC §4.3.4 default behavior.
func TestValidate_DefaultsApplied(t *testing.T) {
	r := R2Alias{Bucket: "b", Endpoint: "https://x"}
	if err := r.Validate(); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if r.Region != "auto" {
		t.Errorf("Region default: want \"auto\", got %q", r.Region)
	}
	if r.CacheTTL != 15*time.Second {
		t.Errorf("CacheTTL default: want 15s, got %s", r.CacheTTL)
	}
	if r.CacheMaxEntries != 10000 {
		t.Errorf("CacheMaxEntries default: want 10000, got %d", r.CacheMaxEntries)
	}
	if r.PreviewSuffix != "--preview" {
		t.Errorf("PreviewSuffix default: want \"--preview\", got %q", r.PreviewSuffix)
	}
	if r.RootDomain != "freecode.camp" {
		t.Errorf("RootDomain default: want \"freecode.camp\", got %q", r.RootDomain)
	}
	if r.DeployIDRegex != `^[A-Za-z0-9._-]{1,64}$` {
		t.Errorf("DeployIDRegex default mismatch, got %q", r.DeployIDRegex)
	}
	if r.deployIDRe == nil {
		t.Errorf("deployIDRe should be compiled after Validate()")
	}
}

// TestValidate_NegativeCacheParams covers the acceptance criterion:
// "GIVEN Validate() runs with CacheTTL <= 0 or CacheMaxEntries <= 0 THEN
// Validate returns an error".
// Note: zero values trigger defaults (legitimate) — only negatives error.
func TestValidate_NegativeCacheParams(t *testing.T) {
	cases := []struct {
		name    string
		r       R2Alias
		wantErr string
	}{
		{
			"negative CacheTTL",
			R2Alias{Bucket: "b", Endpoint: "https://x", CacheTTL: -1 * time.Second},
			"cache_ttl must be > 0",
		},
		{
			"negative CacheMaxEntries",
			R2Alias{Bucket: "b", Endpoint: "https://x", CacheMaxEntries: -1},
			"cache_max_entries must be > 0",
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			err := c.r.Validate()
			if err == nil {
				t.Fatalf("expected error containing %q, got nil", c.wantErr)
			}
			if !strings.Contains(err.Error(), c.wantErr) {
				t.Fatalf("expected error containing %q, got %q", c.wantErr, err.Error())
			}
		})
	}
}

// TestValidate_BadRegex asserts that a malformed deploy_id_regex surfaces as
// a config error instead of a request-time panic.
func TestValidate_BadRegex(t *testing.T) {
	r := R2Alias{Bucket: "b", Endpoint: "https://x", DeployIDRegex: "[unterminated"}
	err := r.Validate()
	if err == nil || !strings.Contains(err.Error(), "deploy_id_regex") {
		t.Fatalf("expected deploy_id_regex error, got %v", err)
	}
}

// TestUnmarshalCaddyfile_FullBlock covers the full grammar from the directive.
// Corresponds to the acceptance criterion that a Caddyfile with all options
// parses without error (the `caddy adapt` check on the exit criterion).
func TestUnmarshalCaddyfile_FullBlock(t *testing.T) {
	const input = `r2_alias {
		bucket foo
		endpoint https://x
		region auto
		access_key_id k
		secret_access_key s
		cache_ttl 15s
		cache_max_entries 10000
		preview_suffix "--preview"
		root_domain "freecode.camp"
		deploy_id_regex "^[A-Za-z0-9._-]{1,64}$"
	}`
	d := caddyfile.NewTestDispenser(input)
	r := new(R2Alias)
	if err := r.UnmarshalCaddyfile(d); err != nil {
		t.Fatalf("unexpected parse error: %v", err)
	}
	if r.Bucket != "foo" || r.Endpoint != "https://x" || r.Region != "auto" {
		t.Errorf("bucket/endpoint/region mismatch: %+v", r)
	}
	if r.AccessKeyID != "k" || r.SecretAccessKey != "s" {
		t.Errorf("creds mismatch: %+v", r)
	}
	if r.CacheTTL != 15*time.Second {
		t.Errorf("CacheTTL: want 15s, got %s", r.CacheTTL)
	}
	if r.CacheMaxEntries != 10000 {
		t.Errorf("CacheMaxEntries: want 10000, got %d", r.CacheMaxEntries)
	}
	if r.PreviewSuffix != "--preview" {
		t.Errorf("PreviewSuffix mismatch: %q", r.PreviewSuffix)
	}
	if r.RootDomain != "freecode.camp" {
		t.Errorf("RootDomain mismatch: %q", r.RootDomain)
	}
	if r.DeployIDRegex != `^[A-Za-z0-9._-]{1,64}$` {
		t.Errorf("DeployIDRegex mismatch: %q", r.DeployIDRegex)
	}
}

// TestUnmarshalCaddyfile_UnknownToken ensures typos surface at parse time.
func TestUnmarshalCaddyfile_UnknownToken(t *testing.T) {
	const input = `r2_alias {
		bucket foo
		endpoint https://x
		wat wrong
	}`
	d := caddyfile.NewTestDispenser(input)
	r := new(R2Alias)
	err := r.UnmarshalCaddyfile(d)
	if err == nil || !strings.Contains(err.Error(), "unknown r2_alias sub-directive") {
		t.Fatalf("expected unknown-directive error, got %v", err)
	}
}

// TestCaddyModule_ID asserts the module registers at the documented ID.
// (Lightweight sanity check; the real smoke test is `caddy list-modules`
// after xcaddy build in T05.)
func TestCaddyModule_ID(t *testing.T) {
	info := R2Alias{}.CaddyModule()
	if info.ID != "http.handlers.r2_alias" {
		t.Fatalf("CaddyModule ID: want http.handlers.r2_alias, got %s", info.ID)
	}
	if info.New == nil || info.New() == nil {
		t.Fatalf("CaddyModule.New must produce a non-nil instance")
	}
}

// --- ServeHTTP tests -------------------------------------------------------
//
// These tests bypass Provision (which loads AWS SDK config) by hand-wiring
// the post-Provision state: deployIDRe compiled, cache constructed, logger
// set, fetcher stub injected. This keeps the test suite independent of the
// AWS SDK and network.

// newProvisionedForTest returns an R2Alias in the same post-Provision state
// a real Caddy startup would leave it in, but without touching the AWS SDK.
// Tests assign r.fetcher to control cache-miss behavior.
func newProvisionedForTest(t *testing.T) *R2Alias {
	t.Helper()
	r := &R2Alias{
		Bucket:          "test-bucket",
		Endpoint:        "https://r2.example",
		Region:          "auto",
		RootDomain:      "freecode.camp",
		PreviewSuffix:   "--preview",
		DeployIDRegex:   `^[A-Za-z0-9._-]{1,64}$`,
		CacheTTL:        1 * time.Second,
		CacheMaxEntries: 10,
		logger:          zap.NewNop(),
	}
	r.deployIDRe = regexp.MustCompile(r.DeployIDRegex)
	r.cache = newAliasCache(r.CacheMaxEntries, r.CacheTTL)
	return r
}

// capturingNext records the path the handler chain sees after r2_alias
// rewrites. Returning nil mimics a successful downstream response.
type capturingNext struct {
	called bool
	path   string
}

func (c *capturingNext) asHandler() caddyhttp.Handler {
	return caddyhttp.HandlerFunc(func(_ http.ResponseWriter, req *http.Request) error {
		c.called = true
		c.path = req.URL.Path
		return nil
	})
}

func stubFetcher(entry aliasEntry, err error) func(context.Context, string) (aliasEntry, error) {
	return func(context.Context, string) (aliasEntry, error) { return entry, err }
}

// handlerStatus extracts the HTTP status from a returned caddyhttp error.
func handlerStatus(t *testing.T, err error) int {
	t.Helper()
	if err == nil {
		return http.StatusOK
	}
	var he caddyhttp.HandlerError
	if !errors.As(err, &he) {
		t.Fatalf("expected caddyhttp.HandlerError, got %T: %v", err, err)
	}
	return he.StatusCode
}

func TestServeHTTP_RewriteProduction(t *testing.T) {
	t.Parallel()
	r := newProvisionedForTest(t)
	r.fetcher = stubFetcher(aliasEntry{DeployID: "20260501-120000-a1b2c3d", Present: true}, nil)

	req := httptest.NewRequest(http.MethodGet, "/assets/x.js", nil)
	req.Host = "hello-world.freecode.camp"
	rec := httptest.NewRecorder()
	next := &capturingNext{}

	if err := r.ServeHTTP(rec, req, next.asHandler()); err != nil {
		t.Fatalf("ServeHTTP: %v", err)
	}
	if !next.called {
		t.Fatal("next handler not called")
	}
	want := "/hello-world.freecode.camp/deploys/20260501-120000-a1b2c3d/assets/x.js"
	if next.path != want {
		t.Fatalf("path rewrite: want %q, got %q", want, next.path)
	}
}

func TestServeHTTP_RewritePreview(t *testing.T) {
	t.Parallel()
	r := newProvisionedForTest(t)
	r.fetcher = stubFetcher(aliasEntry{DeployID: "20260501-130000-z9y8x7w", Present: true}, nil)

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Host = "hello-world--preview.freecode.camp"
	rec := httptest.NewRecorder()
	next := &capturingNext{}

	if err := r.ServeHTTP(rec, req, next.asHandler()); err != nil {
		t.Fatalf("ServeHTTP: %v", err)
	}
	// Site key is the PRODUCTION subdomain even though the request hit the
	// --preview host — deploys are shared, only the alias file differs.
	want := "/hello-world.freecode.camp/deploys/20260501-130000-z9y8x7w/"
	if next.path != want {
		t.Fatalf("path rewrite: want %q, got %q", want, next.path)
	}
}

func TestServeHTTP_RootPathRewrite(t *testing.T) {
	t.Parallel()
	r := newProvisionedForTest(t)
	r.fetcher = stubFetcher(aliasEntry{DeployID: "v1", Present: true}, nil)

	// Empty path — file_server treats `/site/deploys/id/` as an index lookup,
	// so the rewrite must produce a trailing slash.
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Host = "site-a.freecode.camp"
	rec := httptest.NewRecorder()
	next := &capturingNext{}

	_ = r.ServeHTTP(rec, req, next.asHandler())
	want := "/site-a.freecode.camp/deploys/v1/"
	if next.path != want {
		t.Fatalf("root path rewrite: want %q, got %q", want, next.path)
	}
}

func TestServeHTTP_HostNotUnderRootDomain(t *testing.T) {
	t.Parallel()
	r := newProvisionedForTest(t)
	// fetcher must NOT be called — parse failure short-circuits.
	r.fetcher = func(context.Context, string) (aliasEntry, error) {
		t.Fatal("fetcher should not be called on non-root host")
		return aliasEntry{}, nil
	}

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Host = "notaroot.example.com"
	rec := httptest.NewRecorder()
	next := &capturingNext{}

	err := r.ServeHTTP(rec, req, next.asHandler())
	if got := handlerStatus(t, err); got != http.StatusNotFound {
		t.Fatalf("status: want 404, got %d", got)
	}
	if next.called {
		t.Fatal("next should not be called on parse failure")
	}
}

func TestServeHTTP_AliasMissing(t *testing.T) {
	t.Parallel()
	r := newProvisionedForTest(t)
	r.fetcher = stubFetcher(aliasEntry{Present: false}, nil)

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Host = "dead-site.freecode.camp"
	rec := httptest.NewRecorder()
	next := &capturingNext{}

	err := r.ServeHTTP(rec, req, next.asHandler())
	if got := handlerStatus(t, err); got != http.StatusNotFound {
		t.Fatalf("status: want 404, got %d", got)
	}
	if next.called {
		t.Fatal("next should not be called on missing alias")
	}
}

func TestServeHTTP_DeployIDRejected(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name     string
		deployID string
	}{
		{"contains dot-dot", "bad..name"},
		{"contains slash", "v1/etc/passwd"},
		{"over 64 chars", strings.Repeat("x", 65)},
		{"empty-ish space only", "   "}, // fetchAlias trims, but defense-in-depth
	}
	for _, c := range cases {
		c := c
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			r := newProvisionedForTest(t)
			r.fetcher = stubFetcher(aliasEntry{DeployID: c.deployID, Present: true}, nil)

			req := httptest.NewRequest(http.MethodGet, "/", nil)
			req.Host = "site-a.freecode.camp"
			rec := httptest.NewRecorder()
			next := &capturingNext{}

			err := r.ServeHTTP(rec, req, next.asHandler())
			if got := handlerStatus(t, err); got != http.StatusNotFound {
				t.Fatalf("status for %q: want 404, got %d", c.deployID, got)
			}
			if next.called {
				t.Fatalf("next should not be called for rejected deploy id %q", c.deployID)
			}
		})
	}
}

func TestServeHTTP_S3ServerError(t *testing.T) {
	t.Parallel()
	r := newProvisionedForTest(t)
	r.fetcher = stubFetcher(aliasEntry{}, errS3ServerError)

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Host = "site-a.freecode.camp"
	rec := httptest.NewRecorder()
	next := &capturingNext{}

	err := r.ServeHTTP(rec, req, next.asHandler())
	if got := handlerStatus(t, err); got != http.StatusServiceUnavailable {
		t.Fatalf("status: want 503, got %d", got)
	}
	if got := rec.Header().Get("Retry-After"); got != "30" {
		t.Errorf("Retry-After: want 30, got %q", got)
	}
}

func TestServeHTTP_OtherFetchError(t *testing.T) {
	t.Parallel()
	r := newProvisionedForTest(t)
	r.fetcher = stubFetcher(aliasEntry{}, errors.New("unexpected failure"))

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Host = "site-a.freecode.camp"
	rec := httptest.NewRecorder()
	next := &capturingNext{}

	err := r.ServeHTTP(rec, req, next.asHandler())
	if got := handlerStatus(t, err); got != http.StatusInternalServerError {
		t.Fatalf("status: want 500, got %d", got)
	}
}

func TestServeHTTP_PanicRecovered(t *testing.T) {
	t.Parallel()
	r := newProvisionedForTest(t)
	r.fetcher = func(context.Context, string) (aliasEntry, error) {
		panic("boom")
	}

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Host = "site-a.freecode.camp"
	rec := httptest.NewRecorder()
	next := &capturingNext{}

	// The test itself must not panic — the handler must catch it.
	err := r.ServeHTTP(rec, req, next.asHandler())
	if got := handlerStatus(t, err); got != http.StatusInternalServerError {
		t.Fatalf("status: want 500 after panic recovery, got %d", got)
	}
}
