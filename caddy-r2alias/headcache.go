package r2alias

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"time"

	"github.com/hashicorp/golang-lru/v2/expirable"
	"golang.org/x/sync/singleflight"
)

const (
	defaultHeadCacheMaxEntries = 50000
	defaultHeadCacheTTL        = time.Hour
)

type headEntry struct {
	obj     *r2Object
	missing bool
}

type headCache struct {
	lru *expirable.LRU[string, headEntry]
	sf  singleflight.Group
}

func newHeadCache(size int, ttl time.Duration) *headCache {
	if size <= 0 {
		size = defaultHeadCacheMaxEntries
	}
	if ttl <= 0 {
		ttl = defaultHeadCacheTTL
	}
	return &headCache{lru: expirable.NewLRU[string, headEntry](size, nil, ttl)}
}

func (c *headCache) Store(key string, obj *r2Object) {
	meta := *obj
	meta.Body = nil
	c.lru.Add(key, headEntry{obj: &meta})
}

func (c *headCache) Resolve(
	ctx context.Context,
	key string,
	fetchFn func(context.Context) (*r2Object, error),
) (*r2Object, error) {
	if entry, ok := c.lru.Get(key); ok {
		recordHeadLookup(resultHit)
		return entry.answer()
	}
	recordHeadLookup(resultMiss)
	ch := c.sf.DoChan(key, func() (val any, err error) {
		defer func() {
			if rec := recover(); rec != nil {
				err = fmt.Errorf("caddy.fs.r2: head fetch panic: %v", rec)
			}
		}()
		if entry, ok := c.lru.Get(key); ok {
			return entry, nil
		}
		fetchCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), opTimeout)
		defer cancel()
		obj, ferr := fetchFn(fetchCtx)
		if errors.Is(ferr, fs.ErrNotExist) {
			entry := headEntry{missing: true}
			c.lru.Add(key, entry)
			return entry, nil
		}
		if ferr != nil {
			return headEntry{}, ferr
		}
		entry := headEntry{obj: obj}
		c.lru.Add(key, entry)
		return entry, nil
	})
	select {
	case res := <-ch:
		if res.Err != nil {
			return nil, res.Err
		}
		return res.Val.(headEntry).answer()
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}

func (e headEntry) answer() (*r2Object, error) {
	if e.missing {
		return nil, fmt.Errorf("caddy.fs.r2: %w", fs.ErrNotExist)
	}
	return e.obj, nil
}
