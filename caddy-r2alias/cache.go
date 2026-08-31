package r2alias

import (
	"context"
	"fmt"
	"time"

	"github.com/hashicorp/golang-lru/v2/expirable"
	"golang.org/x/sync/singleflight"
)

// aliasCache is a bounded LRU with per-entry TTL and singleflight stampede
// control. It holds both hit and missing-alias sentinel entries so scan
// traffic against dead sites is absorbed by the cache rather than amplified
// to R2.
type aliasCache struct {
	lru          *expirable.LRU[string, aliasEntry]
	sf           singleflight.Group
	fetchTimeout time.Duration
}

// newAliasCache clamps a non-positive bound to its default. expirable.NewLRU
// reads size 0 as unbounded and ttl 0 as never-expiring, and the cache key
// carries the Host header, so an unclamped zero is a memory sink and a stuck
// alias flip.
func newAliasCache(size int, ttl, fetchTimeout time.Duration) *aliasCache {
	if size <= 0 {
		size = defaultCacheMaxEntries
	}
	if ttl <= 0 {
		ttl = defaultCacheTTL
	}
	if fetchTimeout <= 0 {
		fetchTimeout = defaultFetchTimeout
	}
	return &aliasCache{
		lru:          expirable.NewLRU[string, aliasEntry](size, nil, ttl),
		fetchTimeout: fetchTimeout,
	}
}

func cacheKey(bucket, site, aliasName string) string {
	return bucket + "/" + site + "/" + aliasName
}

// Resolve returns the cached entry or invokes fetchFn (coalesced via
// singleflight). Errors are never cached — sticky errors would amplify
// upstream outages across the TTL window.
//
// The shared flight runs on a context detached from every caller and bounded
// by fetchTimeout, so whichever caller happened to start it cannot cancel the
// result the others are waiting on. Each caller still honours its own context.
func (c *aliasCache) Resolve(
	ctx context.Context,
	bucket, site, aliasName string,
	fetchFn func(context.Context, string) (aliasEntry, error),
) (aliasEntry, error) {
	key := cacheKey(bucket, site, aliasName)

	if entry, ok := c.lru.Get(key); ok {
		return entry, nil
	}

	ch := c.sf.DoChan(key, func() (val any, err error) {
		// A DoChan flight re-panics on a detached goroutine that no caller
		// frame can recover, so ServeHTTP's own recover cannot see it and the
		// process dies. Convert it here to keep that guarantee.
		defer func() {
			if rec := recover(); rec != nil {
				err = fmt.Errorf("r2_alias: alias fetch panic: %v", rec)
			}
		}()

		// Re-check inside the flight: a concurrent winner may have populated
		// the cache between our miss and acquiring the singleflight slot.
		if entry, ok := c.lru.Get(key); ok {
			return entry, nil
		}
		fetchCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), c.fetchTimeout)
		defer cancel()

		entry, ferr := fetchFn(fetchCtx, key)
		if ferr != nil {
			return aliasEntry{}, ferr
		}
		c.lru.Add(key, entry)
		return entry, nil
	})

	select {
	case res := <-ch:
		if res.Err != nil {
			return aliasEntry{}, res.Err
		}
		return res.Val.(aliasEntry), nil
	case <-ctx.Done():
		return aliasEntry{}, ctx.Err()
	}
}
