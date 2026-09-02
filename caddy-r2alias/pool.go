package r2alias

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"maps"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsretry "github.com/aws/aws-sdk-go-v2/aws/retry"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/smithy-go/logging"
	"github.com/caddyserver/caddy/v2"
	"go.uber.org/zap"
)

var (
	s3Clients   = caddy.NewUsagePool()
	aliasCaches = caddy.NewUsagePool()
)

type r2ClientConfig struct {
	Bucket          string
	Endpoint        string
	Region          string
	AccessKeyID     string
	SecretAccessKey string
	UsePathStyle    bool
	MaxAttempts     int
	MaxBackoff      time.Duration
}

func (c r2ClientConfig) poolKey() string {
	sum := sha256.Sum256([]byte(strconv.Quote(c.Bucket) +
		strconv.Quote(c.Endpoint) +
		strconv.Quote(c.Region) +
		strconv.Quote(c.AccessKeyID) +
		strconv.Quote(c.SecretAccessKey) +
		strconv.FormatBool(c.UsePathStyle) +
		strconv.Itoa(c.MaxAttempts) +
		c.MaxBackoff.String()))
	return "r2-client-" + hex.EncodeToString(sum[:])
}

type pooledS3Client struct {
	client *s3.Client
}

func (pooledS3Client) Destruct() error { return nil }

type pooledAliasCache struct {
	cache *aliasCache
}

// https://github.com/hashicorp/golang-lru/blob/v2.0.7/expirable/expirable_lru.go#L79-L80
func (p pooledAliasCache) Destruct() error {
	p.cache.lru.Purge()
	return nil
}

type sdkLogger struct {
	logger *zap.Logger
}

func (l sdkLogger) Logf(classification logging.Classification, format string, v ...any) {
	if l.logger == nil {
		return
	}
	msg := fmt.Sprintf(format, v...)
	if classification == logging.Warn {
		l.logger.Warn("aws sdk", zap.String("message", msg))
		return
	}
	l.logger.Debug("aws sdk", zap.String("message", msg))
}

func newBudgetedRetryer(maxAttempts int, maxBackoff time.Duration) aws.Retryer {
	codes := make(map[int]struct{}, len(awsretry.DefaultRetryableHTTPStatusCodes)+1)
	for code := range awsretry.DefaultRetryableHTTPStatusCodes {
		codes[code] = struct{}{}
	}
	codes[http.StatusTooManyRequests] = struct{}{}

	return awsretry.NewStandard(func(o *awsretry.StandardOptions) {
		o.MaxAttempts = maxAttempts
		o.MaxBackoff = maxBackoff
		o.Retryables = append([]awsretry.IsErrorRetryable(nil), awsretry.DefaultRetryables...)
		for i, retryable := range o.Retryables {
			if _, ok := retryable.(awsretry.RetryableHTTPStatusCode); ok {
				o.Retryables[i] = awsretry.RetryableHTTPStatusCode{Codes: codes}
			}
		}
	})
}

func resolvePlaceholders(fields map[string]*string) error {
	repl := caddy.NewReplacer()
	for _, name := range slices.Sorted(maps.Keys(fields)) {
		field := fields[name]
		if field == nil || !strings.Contains(*field, "{") {
			continue
		}
		resolved, err := repl.ReplaceOrErr(*field, true, true)
		if err != nil {
			return fmt.Errorf("%s: unresolved placeholder", name)
		}
		*field = resolved
	}
	return nil
}

func sharedS3Client(ctx caddy.Context, cfg r2ClientConfig, logger *zap.Logger) (*s3.Client, string, error) {
	key := cfg.poolKey()
	value, _, err := s3Clients.LoadOrNew(key, func() (caddy.Destructor, error) {
		awsCfg, loadErr := config.LoadDefaultConfig(ctx,
			config.WithRegion(cfg.Region),
			config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(
				cfg.AccessKeyID, cfg.SecretAccessKey, "",
			)),
			config.WithLogger(sdkLogger{logger: logger}),
			config.WithRetryer(func() aws.Retryer {
				return newBudgetedRetryer(cfg.MaxAttempts, cfg.MaxBackoff)
			}),
		)
		if loadErr != nil {
			return nil, loadErr
		}
		return pooledS3Client{client: s3.NewFromConfig(awsCfg, func(o *s3.Options) {
			o.BaseEndpoint = aws.String(cfg.Endpoint)
			o.UsePathStyle = cfg.UsePathStyle
			o.DisableLogOutputChecksumValidationSkipped = true
		})}, nil
	})
	if err != nil {
		return nil, "", err
	}
	return value.(pooledS3Client).client, key, nil
}

func sharedAliasCache(cfg r2ClientConfig, size int, ttl, fetchTimeout time.Duration) (*aliasCache, string) {
	sum := sha256.Sum256([]byte(cfg.poolKey() +
		strconv.Itoa(size) + ttl.String() + fetchTimeout.String()))
	key := "r2-alias-cache-" + hex.EncodeToString(sum[:])
	value, _, _ := aliasCaches.LoadOrNew(key, func() (caddy.Destructor, error) {
		return pooledAliasCache{cache: newAliasCache(size, ttl, fetchTimeout)}, nil
	})
	return value.(pooledAliasCache).cache, key
}
