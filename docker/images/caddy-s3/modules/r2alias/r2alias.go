// Package r2alias implements a Caddy HTTP handler that resolves alias files
// in a Cloudflare R2 bucket and rewrites the request path to the target
// deploy prefix. See RFC docs/rfc/gxy-cassiopeia.md §4.3 for the full design.
package r2alias

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awshttp "github.com/aws/aws-sdk-go-v2/aws/transport/http"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	s3types "github.com/aws/aws-sdk-go-v2/service/s3/types"
	"github.com/caddyserver/caddy/v2"
	"github.com/caddyserver/caddy/v2/caddyconfig/caddyfile"
	"github.com/caddyserver/caddy/v2/caddyconfig/httpcaddyfile"
	"github.com/caddyserver/caddy/v2/modules/caddyhttp"
	"go.uber.org/zap"
)

// errS3ServerError is wrapped around any R2/S3 response with a 5xx status so
// ServeHTTP can distinguish upstream outages (→ 503 with Retry-After) from
// unexpected errors (→ 500). Errors are never cached — sticky 5xx would
// amplify R2 outages across the whole LRU window.
var errS3ServerError = errors.New("r2_alias: upstream 5xx")

// maxAliasBodyBytes caps how much of an alias object we read. Legitimate
// alias files are deploy-ID strings (≤ 64 bytes); this bound keeps a
// misbehaving or malicious object from consuming memory.
const maxAliasBodyBytes = 1024

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

	client *s3.Client
	cache  *aliasCache
	logger *zap.Logger

	// deployIDRe is the compiled DeployIDRegex; populated by Validate.
	deployIDRe *regexp.Regexp

	// fetcher is the cache-miss path invoked by aliasCache.Resolve. Provision
	// sets it to fetchAlias; tests substitute a stub so ServeHTTP can be
	// exercised without an S3 client.
	fetcher func(ctx context.Context, key string) (aliasEntry, error)
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

// Provision loads the AWS SDK config, constructs the R2-targeted S3 client
// (path-style addressing, custom endpoint), initializes the alias cache,
// attaches the logger, and wires the default fetcher. Called once at startup
// after Validate.
func (r *R2Alias) Provision(ctx caddy.Context) error {
	awsCfg, err := config.LoadDefaultConfig(ctx,
		config.WithRegion(r.Region),
		config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(
			r.AccessKeyID, r.SecretAccessKey, "",
		)),
	)
	if err != nil {
		return fmt.Errorf("r2_alias: load aws config: %w", err)
	}
	r.client = s3.NewFromConfig(awsCfg, func(o *s3.Options) {
		o.BaseEndpoint = aws.String(r.Endpoint)
		o.UsePathStyle = true
	})

	r.cache = newAliasCache(r.CacheMaxEntries, r.CacheTTL)
	r.logger = ctx.Logger()
	if r.fetcher == nil {
		r.fetcher = r.fetchAlias
	}
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

// ServeHTTP resolves the alias for the request Host, validates the deploy ID,
// rewrites req.URL.Path to `/{site}/deploys/{deployID}{origPath}`, and hands
// off to the next handler (expected to be `file_server { fs r2 }`).
//
// Error responses:
//   - Host not under RootDomain or empty site label → 404
//   - Alias missing (R2 NoSuchKey) → 404
//   - Deploy ID fails regex, contains `..`, or contains `/` → 404
//   - R2 5xx → 503 with `Retry-After: 30`
//   - Any other resolver error → 500
//
// A defer-recover catches panics from the fetcher or the rewrite path so a
// bug in this module never crashes the Caddy process.
func (r *R2Alias) ServeHTTP(w http.ResponseWriter, req *http.Request, next caddyhttp.Handler) (err error) {
	defer func() {
		if rec := recover(); rec != nil {
			r.logger.Error("r2_alias panic recovered",
				zap.Any("panic", rec),
				zap.String("host", req.Host),
				zap.String("path", req.URL.Path),
			)
			err = caddyhttp.Error(http.StatusInternalServerError, fmt.Errorf("r2_alias: panic recovered"))
		}
	}()

	site, aliasName, parseErr := parseSiteAndAlias(req.Host, r.RootDomain, r.PreviewSuffix)
	if parseErr != nil {
		return caddyhttp.Error(http.StatusNotFound, parseErr)
	}

	entry, resolveErr := r.cache.Resolve(req.Context(), r.Bucket, site, aliasName, r.fetcher)
	if resolveErr != nil {
		fields := []zap.Field{
			zap.Error(resolveErr),
			zap.String("site", site),
			zap.String("alias_name", aliasName),
		}
		if errors.Is(resolveErr, errS3ServerError) {
			w.Header().Set("Retry-After", "30")
			r.logger.Error("r2_alias upstream 5xx", fields...)
			return caddyhttp.Error(http.StatusServiceUnavailable, resolveErr)
		}
		r.logger.Error("r2_alias resolve error", fields...)
		return caddyhttp.Error(http.StatusInternalServerError, resolveErr)
	}

	if !entry.Present {
		return caddyhttp.Error(http.StatusNotFound, fmt.Errorf("r2_alias: no alias for %s/%s", site, aliasName))
	}

	if !r.deployIDRe.MatchString(entry.DeployID) ||
		strings.Contains(entry.DeployID, "..") ||
		strings.ContainsRune(entry.DeployID, '/') {
		r.logger.Warn("r2_alias deploy id rejected",
			zap.String("site", site),
			zap.String("alias_name", aliasName),
			zap.String("deploy_id", entry.DeployID),
		)
		return caddyhttp.Error(http.StatusNotFound, fmt.Errorf("r2_alias: deploy id rejected"))
	}

	origPath := req.URL.Path
	if origPath == "" {
		origPath = "/"
	}
	req.URL.Path = "/" + site + "/deploys/" + entry.DeployID + origPath

	return next.ServeHTTP(w, req)
}

// fetchAlias reads `{site}/{aliasName}` from R2 and returns the decoded entry.
// The cache key composed by aliasCache has the form `bucket/site/aliasName`;
// the bucket prefix is stripped before issuing the S3 GetObject call.
//
// R2 responses map to aliasEntry as follows:
//   - 200 with non-empty trimmed body → Present: true, DeployID: trimmed body
//   - 200 with empty / whitespace-only body → Present: false (treated as missing)
//   - NoSuchKey → Present: false (load-bearing sentinel; subdomain scans cached)
//   - 5xx → errS3ServerError wrapped error
//   - Other errors → wrapped error (ServeHTTP maps to 500)
func (r *R2Alias) fetchAlias(ctx context.Context, cacheKey string) (aliasEntry, error) {
	// Cache keys are composed as `bucket/site/aliasName`. We only need the
	// bucket-relative object key (`site/aliasName`) for S3.
	s3Key := cacheKey
	if i := strings.IndexByte(cacheKey, '/'); i >= 0 {
		s3Key = cacheKey[i+1:]
	}

	out, err := r.client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(r.Bucket),
		Key:    aws.String(s3Key),
	})
	if err != nil {
		var nsk *s3types.NoSuchKey
		if errors.As(err, &nsk) {
			return aliasEntry{Present: false}, nil
		}
		var respErr *awshttp.ResponseError
		if errors.As(err, &respErr) && respErr.HTTPStatusCode() >= 500 {
			return aliasEntry{}, fmt.Errorf("%w: %w", errS3ServerError, err)
		}
		return aliasEntry{}, fmt.Errorf("r2_alias: s3 GetObject %s: %w", s3Key, err)
	}
	defer func() { _ = out.Body.Close() }()

	body, readErr := io.ReadAll(io.LimitReader(out.Body, maxAliasBodyBytes))
	if readErr != nil {
		return aliasEntry{}, fmt.Errorf("r2_alias: read alias body %s: %w", s3Key, readErr)
	}

	deployID := strings.TrimSpace(string(body))
	if deployID == "" {
		return aliasEntry{Present: false}, nil
	}
	return aliasEntry{DeployID: deployID, Present: true}, nil
}

// Interface guards (compile-time assertions that R2Alias implements the
// expected Caddy interfaces).
var (
	_ caddy.Provisioner           = (*R2Alias)(nil)
	_ caddy.Validator             = (*R2Alias)(nil)
	_ caddyfile.Unmarshaler       = (*R2Alias)(nil)
	_ caddyhttp.MiddlewareHandler = (*R2Alias)(nil)
)
