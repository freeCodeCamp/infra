package r2alias

import (
	"context"
	"time"

	"github.com/hashicorp/golang-lru/v2/expirable"
	"golang.org/x/sync/singleflight"
)

// aliasCache wraps a bounded LRU with per-entry TTL + singleflight stampede
// control. It holds both hit entries (Present=true) and missing-alias sentinels
// (Present=false) — the latter absorb subdomain-scan traffic against dead sites
// (RFC §4.3.5).
//
// The cache is agnostic to how entries are fetched: Resolve accepts a fetchFn
// that returns an aliasEntry for a given composed key. This keeps the cache
// testable with stub fetchers and keeps the S3 call site in the handler
// (ServeHTTP, Task 03) rather than here.
type aliasCache struct {
	lru *expirable.LRU[string, aliasEntry]
	sf  singleflight.Group
}

// newAliasCache constructs an aliasCache with fixed capacity and per-entry TTL.
// Size and ttl must be > 0 (enforced by R2Alias.Validate at config-time).
func newAliasCache(size int, ttl time.Duration) *aliasCache {
	return &aliasCache{
		lru: expirable.NewLRU[string, aliasEntry](size, nil, ttl),
	}
}

// key composes the cache key from bucket + site + aliasName. Exposed as an
// unexported helper so tests can verify key composition without reaching
// into the LRU.
func cacheKey(bucket, site, aliasName string) string {
	return bucket + "/" + site + "/" + aliasName
}

// Resolve returns the cached aliasEntry for the composed key, or invokes
// fetchFn once (with singleflight coalescing concurrent misses for the same
// key) and caches the result. Errors are NOT cached — the next call retries.
//
// Both Present=true and Present=false results are cached for the full TTL.
// The missing-alias sentinel (Present=false) is load-bearing: subdomain-scan
// traffic against dead sites is bounded by the cache TTL rather than
// amplifying R2 request volume.
func (c *aliasCache) Resolve(
	ctx context.Context,
	bucket, site, aliasName string,
	fetchFn func(context.Context, string) (aliasEntry, error),
) (aliasEntry, error) {
	key := cacheKey(bucket, site, aliasName)

	if entry, ok := c.lru.Get(key); ok {
		return entry, nil
	}

	result, err, _ := c.sf.Do(key, func() (any, error) {
		// Re-check inside the flight: a concurrent winner may have populated
		// the cache between our miss and acquiring the singleflight slot.
		if entry, ok := c.lru.Get(key); ok {
			return entry, nil
		}
		entry, ferr := fetchFn(ctx, key)
		if ferr != nil {
			return aliasEntry{}, ferr
		}
		c.lru.Add(key, entry)
		return entry, nil
	})
	if err != nil {
		return aliasEntry{}, err
	}
	return result.(aliasEntry), nil
}
