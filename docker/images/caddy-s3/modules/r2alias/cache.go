package r2alias

import (
	"context"
	"time"

	"github.com/hashicorp/golang-lru/v2/expirable"
	"golang.org/x/sync/singleflight"
)

// aliasCache is a bounded LRU with per-entry TTL and singleflight stampede
// control. It holds both hit and missing-alias sentinel entries so scan
// traffic against dead sites is absorbed by the cache rather than amplified
// to R2.
type aliasCache struct {
	lru *expirable.LRU[string, aliasEntry]
	sf  singleflight.Group
}

func newAliasCache(size int, ttl time.Duration) *aliasCache {
	return &aliasCache{
		lru: expirable.NewLRU[string, aliasEntry](size, nil, ttl),
	}
}

func cacheKey(bucket, site, aliasName string) string {
	return bucket + "/" + site + "/" + aliasName
}

// Resolve returns the cached entry or invokes fetchFn (coalesced via
// singleflight). Errors are never cached — sticky errors would amplify
// upstream outages across the TTL window.
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
