// Package r2alias implements Caddy modules for serving Universe static
// constellations from Cloudflare R2: a middleware handler that resolves
// alias files and rewrites the request path, plus a sibling filesystem
// module that streams object bytes.
package r2alias

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awshttp "github.com/aws/aws-sdk-go-v2/aws/transport/http"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/caddyserver/caddy/v2"
	"github.com/caddyserver/caddy/v2/caddyconfig/caddyfile"
	"github.com/caddyserver/caddy/v2/caddyconfig/httpcaddyfile"
	"github.com/caddyserver/caddy/v2/modules/caddyhttp"
	"go.uber.org/zap"
)

// errS3ServerError marks any upstream 5xx so ServeHTTP can answer 503 with
// Retry-After; all other errors map to 500. Never cached — sticky 5xx would
// amplify an R2 outage across the whole LRU window.
var errS3ServerError = errors.New("r2_alias: upstream 5xx")

// maxAliasBodyBytes caps the alias object read. Legitimate alias files are
// deploy-ID strings (≤ 64 bytes); the bound defends against a misbehaving
// or malicious object.
const maxAliasBodyBytes = 1024

const (
	defaultCacheMaxEntries  = 10000
	defaultCacheTTL         = caddy.Duration(15 * time.Second)
	defaultFetchTimeout     = caddy.Duration(2 * time.Second)
	defaultRegion           = "auto"
	defaultPreviewSubdomain = "preview"
	defaultRootDomain       = "freecode.camp"
	defaultDeployIDRegex    = `^[A-Za-z0-9._-]{1,64}$`
	defaultRetryAfter       = "30"
)

const aliasRetryAttempts = 2

type R2Alias struct {
	Bucket           string         `json:"bucket"`
	Endpoint         string         `json:"endpoint"`
	Region           string         `json:"region"`
	AccessKeyID      string         `json:"access_key_id,omitempty"`
	SecretAccessKey  string         `json:"secret_access_key,omitempty"`
	CacheTTL         caddy.Duration `json:"cache_ttl,omitempty"`
	CacheMaxEntries  int            `json:"cache_max_entries,omitempty"`
	PreviewSubdomain string         `json:"preview_subdomain,omitempty"`
	RootDomain       string         `json:"root_domain,omitempty"`
	DeployIDRegex    string         `json:"deploy_id_regex,omitempty"`
	// FetchTimeout is read once, by Provision, when it builds the cache. Setting
	// it on a live handler does nothing; rebuild the cache to change it.
	FetchTimeout caddy.Duration `json:"fetch_timeout,omitempty"`

	client     *s3.Client
	clientKey  string
	cache      *aliasCache
	cacheKey   string
	logger     *zap.Logger
	deployIDRe *regexp.Regexp

	// fetcher is the cache-miss path. Provision wires it to fetchAlias;
	// tests swap a stub so ServeHTTP can run without an S3 client.
	fetcher func(ctx context.Context, key string) (aliasEntry, error)
}

// aliasEntry carries the cached resolution. Present=false is the missing-alias
// sentinel that absorbs subdomain-scan traffic against dead sites.
type aliasEntry struct {
	DeployID string
	Present  bool
}

func init() {
	caddy.RegisterModule(R2Alias{})
	httpcaddyfile.RegisterHandlerDirective("r2_alias", parseCaddyfile)
	httpcaddyfile.RegisterDirectiveOrder("r2_alias", httpcaddyfile.Before, "file_server")
}

func (R2Alias) CaddyModule() caddy.ModuleInfo {
	return caddy.ModuleInfo{
		ID:  "http.handlers.r2_alias",
		New: func() caddy.Module { return new(R2Alias) },
	}
}

// applyDefaults fills every unset field. Provision calls it before building
// the cache; caddy runs Provision before Validate (context.go:426, :441), so
// defaults set only in Validate would reach the cache one step too late.
func (r *R2Alias) applyDefaults() {
	if r.Region == "" {
		r.Region = defaultRegion
	}
	if r.CacheTTL == 0 {
		r.CacheTTL = defaultCacheTTL
	}
	if r.CacheMaxEntries == 0 {
		r.CacheMaxEntries = defaultCacheMaxEntries
	}
	if r.PreviewSubdomain == "" {
		r.PreviewSubdomain = defaultPreviewSubdomain
	}
	if r.RootDomain == "" {
		r.RootDomain = defaultRootDomain
	}
	if r.DeployIDRegex == "" {
		r.DeployIDRegex = defaultDeployIDRegex
	}
	if r.FetchTimeout == 0 {
		r.FetchTimeout = defaultFetchTimeout
	}
}

func (r *R2Alias) Provision(ctx caddy.Context) error {
	r.applyDefaults()
	r.logger = ctx.Logger()
	if err := initMetrics(ctx.GetMetricsRegistry()); err != nil {
		return fmt.Errorf("r2_alias: %w", err)
	}

	if err := resolvePlaceholders(map[string]*string{
		"bucket":            &r.Bucket,
		"endpoint":          &r.Endpoint,
		"region":            &r.Region,
		"access_key_id":     &r.AccessKeyID,
		"secret_access_key": &r.SecretAccessKey,
		"root_domain":       &r.RootDomain,
		"preview_subdomain": &r.PreviewSubdomain,
	}); err != nil {
		return fmt.Errorf("r2_alias: %w", err)
	}

	fetchTimeout := time.Duration(r.FetchTimeout)
	clientCfg := r2ClientConfig{
		Bucket:          r.Bucket,
		Endpoint:        r.Endpoint,
		Region:          r.Region,
		AccessKeyID:     r.AccessKeyID,
		SecretAccessKey: r.SecretAccessKey,
		UsePathStyle:    true,
		MaxAttempts:     aliasRetryAttempts,
		MaxBackoff:      fetchTimeout / 4,
	}
	client, clientKey, err := sharedS3Client(ctx, clientCfg, r.logger)
	if err != nil {
		return fmt.Errorf("r2_alias: load aws config: %w", err)
	}
	r.client, r.clientKey = client, clientKey

	r.cache, r.cacheKey = sharedAliasCache(
		clientCfg, r.CacheMaxEntries, time.Duration(r.CacheTTL), fetchTimeout)

	if r.fetcher == nil {
		r.fetcher = r.fetchAlias
	}
	return nil
}

func (r *R2Alias) Cleanup() error {
	var errs []error
	if r.clientKey != "" {
		if _, err := s3Clients.Delete(r.clientKey); err != nil {
			errs = append(errs, err)
		}
	}
	if r.cacheKey != "" {
		if _, err := aliasCaches.Delete(r.cacheKey); err != nil {
			errs = append(errs, err)
		}
	}
	return errors.Join(errs...)
}

func (r *R2Alias) Validate() error {
	if r.Bucket == "" {
		return fmt.Errorf("r2_alias: bucket is required")
	}
	if r.Endpoint == "" {
		return fmt.Errorf("r2_alias: endpoint is required")
	}

	r.applyDefaults()

	if r.CacheTTL <= 0 {
		return fmt.Errorf("r2_alias: cache_ttl must be > 0 (got %s)", time.Duration(r.CacheTTL))
	}
	if r.CacheMaxEntries <= 0 {
		return fmt.Errorf("r2_alias: cache_max_entries must be > 0 (got %d)", r.CacheMaxEntries)
	}
	if r.FetchTimeout <= 0 {
		return fmt.Errorf("r2_alias: fetch_timeout must be > 0 (got %s)", time.Duration(r.FetchTimeout))
	}

	re, err := regexp.Compile(r.DeployIDRegex)
	if err != nil {
		return fmt.Errorf("r2_alias: deploy_id_regex does not compile: %w", err)
	}
	r.deployIDRe = re

	return nil
}

// ServeHTTP wraps the body in defer-recover so a bug in the handler never
// crashes Caddy — this module runs in the request path of every site on
// the galaxy.
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

	site, aliasName, parseErr := parseSiteAndAlias(req.Host, r.RootDomain, r.PreviewSubdomain)
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
		// A deadline is an upstream-is-not-answering signal, not a bug here, so
		// it answers 503 with Retry-After like any other upstream failure.
		if errors.Is(resolveErr, errS3ServerError) ||
			errors.Is(resolveErr, context.DeadlineExceeded) {
			w.Header().Set("Retry-After", retryAfterFrom(resolveErr))
			r.logger.Error("r2_alias upstream unavailable", fields...)
			return caddyhttp.Error(http.StatusServiceUnavailable, resolveErr)
		}
		r.logger.Error("r2_alias resolve error", fields...)
		return caddyhttp.Error(http.StatusInternalServerError, resolveErr)
	}

	if !entry.Present {
		return caddyhttp.Error(http.StatusNotFound, fmt.Errorf("r2_alias: no alias for %s/%s", site, aliasName))
	}

	if !r.deployIDRe.MatchString(entry.DeployID) ||
		entry.DeployID == "." ||
		strings.Contains(entry.DeployID, "..") ||
		strings.ContainsRune(entry.DeployID, '/') {
		r.logger.Warn("r2_alias deploy id rejected",
			zap.String("site", site),
			zap.String("alias_name", aliasName),
			zap.String("deploy_id", entry.DeployID),
		)
		return caddyhttp.Error(http.StatusNotFound, fmt.Errorf("r2_alias: deploy id rejected"))
	}

	w.Header().Set("Etag", strconv.Quote(entry.DeployID))

	// Clean before the join: Caddy leaves req.URL.Path raw, and file_server's
	// SanitizedPathJoin cleans too late to keep `..` inside the deploy prefix.
	origPath := caddyhttp.CleanPath("/"+req.URL.Path, true)
	req.URL.Path = "/" + site + "/deploys/" + entry.DeployID + origPath
	req.URL.RawPath = ""

	return next.ServeHTTP(w, req)
}

func upstreamStatus(err error) (int, bool) {
	var respErr *awshttp.ResponseError
	if !errors.As(err, &respErr) {
		return 0, false
	}
	code := respErr.HTTPStatusCode()
	return code, code >= 500 || code == http.StatusTooManyRequests
}

func retryAfterFrom(err error) string {
	var respErr *awshttp.ResponseError
	if errors.As(err, &respErr) && respErr.Response != nil && respErr.Response.Response != nil {
		if after := respErr.Response.Header.Get("Retry-After"); after != "" {
			return after
		}
	}
	return defaultRetryAfter
}

func (r *R2Alias) fetchAlias(ctx context.Context, cacheKey string) (aliasEntry, error) {
	// Cache keys are `bucket/site/aliasName`; S3 wants `site/aliasName`.
	s3Key := cacheKey
	if i := strings.IndexByte(cacheKey, '/'); i >= 0 {
		s3Key = cacheKey[i+1:]
	}

	out, err := r.client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(r.Bucket),
		Key:    aws.String(s3Key),
	})
	if err != nil {
		if isNoSuchKey(err) {
			recordOperation(opAlias, resultNotFound)
			return aliasEntry{Present: false}, nil
		}
		recordOperation(opAlias, resultError)
		if _, upstream := upstreamStatus(err); upstream {
			return aliasEntry{}, fmt.Errorf("%w: %w", errS3ServerError, err)
		}
		return aliasEntry{}, fmt.Errorf("r2_alias: s3 GetObject %s: %w", s3Key, err)
	}
	recordOperation(opAlias, resultOK)
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

var (
	_ caddy.Provisioner           = (*R2Alias)(nil)
	_ caddy.Validator             = (*R2Alias)(nil)
	_ caddy.CleanerUpper          = (*R2Alias)(nil)
	_ caddyfile.Unmarshaler       = (*R2Alias)(nil)
	_ caddyhttp.MiddlewareHandler = (*R2Alias)(nil)
)
