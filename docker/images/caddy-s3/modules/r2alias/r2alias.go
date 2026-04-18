// Package r2alias implements a Caddy HTTP handler that resolves alias files
// in a Cloudflare R2 bucket and rewrites the request path to the target
// deploy prefix. See RFC docs/rfc/gxy-cassiopeia.md §4.3 for the full design.
//
// This file is the T01 scaffold: module registration, struct definition,
// Validate, and stub Provision + ServeHTTP. T02 adds the bounded LRU +
// singleflight cache; T03 adds the real ServeHTTP implementation.
package r2alias

import (
	"fmt"
	"net/http"
	"regexp"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/caddyserver/caddy/v2"
	"github.com/caddyserver/caddy/v2/caddyconfig/caddyfile"
	"github.com/caddyserver/caddy/v2/caddyconfig/httpcaddyfile"
	"github.com/caddyserver/caddy/v2/modules/caddyhttp"
	"github.com/hashicorp/golang-lru/v2/expirable"
	"go.uber.org/zap"
	"golang.org/x/sync/singleflight"
)

// R2Alias is a Caddy HTTP handler that resolves {site}/{alias_name} files in
// an S3-compatible bucket and rewrites the request path to the target deploy
// prefix. Positioned before file_server so the rewritten path is served by
// a filesystem module (e.g. caddy-fs-s3 with fs r2).
type R2Alias struct {
	Bucket          string        `json:"bucket"`
	Endpoint        string        `json:"endpoint"`
	Region          string        `json:"region"`
	AccessKeyID     string        `json:"access_key_id,omitempty"`
	SecretAccessKey string        `json:"secret_access_key,omitempty"`
	CacheTTL        time.Duration `json:"cache_ttl,omitempty"`
	CacheMaxEntries int           `json:"cache_max_entries,omitempty"`
	PreviewSuffix   string        `json:"preview_suffix,omitempty"`
	RootDomain      string        `json:"root_domain,omitempty"`
	DeployIDRegex   string        `json:"deploy_id_regex,omitempty"`

	client  *s3.Client
	cache   *expirable.LRU[string, aliasEntry]
	sfgroup *singleflight.Group
	logger  *zap.Logger

	// deployIDRe is the compiled DeployIDRegex; populated by Validate.
	deployIDRe *regexp.Regexp
}

// aliasEntry is the cached resolution. Present=true means a valid deploy ID
// was resolved; Present=false is the missing-alias sentinel used to absorb
// scan traffic against dead subdomains.
type aliasEntry struct {
	DeployID string
	Present  bool
}

func init() {
	caddy.RegisterModule(R2Alias{})
	httpcaddyfile.RegisterHandlerDirective("r2_alias", parseCaddyfile)
}

// CaddyModule returns the Caddy module information.
func (R2Alias) CaddyModule() caddy.ModuleInfo {
	return caddy.ModuleInfo{
		ID:  "http.handlers.r2_alias",
		New: func() caddy.Module { return new(R2Alias) },
	}
}

// Provision sets up the S3 client and alias cache. Called once at startup.
// T01 scaffold: no-op. T02 populates s3.Client, expirable.LRU, and the logger.
func (r *R2Alias) Provision(_ caddy.Context) error {
	return nil
}

// Validate enforces configuration invariants and applies defaults for zero values.
// Defaults (per RFC §4.3.4):
//
//	CacheTTL         = 15s
//	CacheMaxEntries  = 10_000
//	PreviewSuffix    = "--preview"
//	RootDomain       = "freecode.camp"
//	DeployIDRegex    = "^[A-Za-z0-9._-]{1,64}$"
//	Region           = "auto"
func (r *R2Alias) Validate() error {
	if r.Bucket == "" {
		return fmt.Errorf("r2_alias: bucket is required")
	}
	if r.Endpoint == "" {
		return fmt.Errorf("r2_alias: endpoint is required")
	}

	if r.Region == "" {
		r.Region = "auto"
	}
	if r.CacheTTL == 0 {
		r.CacheTTL = 15 * time.Second
	}
	if r.CacheMaxEntries == 0 {
		r.CacheMaxEntries = 10000
	}
	if r.PreviewSuffix == "" {
		r.PreviewSuffix = "--preview"
	}
	if r.RootDomain == "" {
		r.RootDomain = "freecode.camp"
	}
	if r.DeployIDRegex == "" {
		r.DeployIDRegex = `^[A-Za-z0-9._-]{1,64}$`
	}

	if r.CacheTTL <= 0 {
		return fmt.Errorf("r2_alias: cache_ttl must be > 0 (got %s)", r.CacheTTL)
	}
	if r.CacheMaxEntries <= 0 {
		return fmt.Errorf("r2_alias: cache_max_entries must be > 0 (got %d)", r.CacheMaxEntries)
	}

	re, err := regexp.Compile(r.DeployIDRegex)
	if err != nil {
		return fmt.Errorf("r2_alias: deploy_id_regex does not compile: %w", err)
	}
	r.deployIDRe = re

	return nil
}

// ServeHTTP implements the handler. T01 scaffold: pass through to next.
// T03 replaces this with the alias resolution + path rewrite logic.
func (r R2Alias) ServeHTTP(w http.ResponseWriter, req *http.Request, next caddyhttp.Handler) error {
	return next.ServeHTTP(w, req)
}

// Interface guards (compile-time assertions that R2Alias implements the
// expected Caddy interfaces).
var (
	_ caddy.Provisioner           = (*R2Alias)(nil)
	_ caddy.Validator             = (*R2Alias)(nil)
	_ caddyfile.Unmarshaler       = (*R2Alias)(nil)
	_ caddyhttp.MiddlewareHandler = (*R2Alias)(nil)
)
