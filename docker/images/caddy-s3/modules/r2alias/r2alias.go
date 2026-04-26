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

// errS3ServerError marks any upstream 5xx so ServeHTTP can answer 503 with
// Retry-After; all other errors map to 500. Never cached — sticky 5xx would
// amplify an R2 outage across the whole LRU window.
var errS3ServerError = errors.New("r2_alias: upstream 5xx")

// maxAliasBodyBytes caps the alias object read. Legitimate alias files are
// deploy-ID strings (≤ 64 bytes); the bound defends against a misbehaving
// or malicious object.
const maxAliasBodyBytes = 1024

type R2Alias struct {
	Bucket           string        `json:"bucket"`
	Endpoint         string        `json:"endpoint"`
	Region           string        `json:"region"`
	AccessKeyID      string        `json:"access_key_id,omitempty"`
	SecretAccessKey  string        `json:"secret_access_key,omitempty"`
	CacheTTL         time.Duration `json:"cache_ttl,omitempty"`
	CacheMaxEntries  int           `json:"cache_max_entries,omitempty"`
	PreviewSubdomain string        `json:"preview_subdomain,omitempty"`
	RootDomain       string        `json:"root_domain,omitempty"`
	DeployIDRegex    string        `json:"deploy_id_regex,omitempty"`

	client     *s3.Client
	cache      *aliasCache
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
}

func (R2Alias) CaddyModule() caddy.ModuleInfo {
	return caddy.ModuleInfo{
		ID:  "http.handlers.r2_alias",
		New: func() caddy.Module { return new(R2Alias) },
	}
}

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
	if r.PreviewSubdomain == "" {
		r.PreviewSubdomain = "preview"
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

var (
	_ caddy.Provisioner           = (*R2Alias)(nil)
	_ caddy.Validator             = (*R2Alias)(nil)
	_ caddyfile.Unmarshaler       = (*R2Alias)(nil)
	_ caddyhttp.MiddlewareHandler = (*R2Alias)(nil)
)
