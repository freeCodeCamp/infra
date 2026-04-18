package r2alias

import (
	"strings"
	"testing"
	"time"

	"github.com/caddyserver/caddy/v2/caddyconfig/caddyfile"
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
