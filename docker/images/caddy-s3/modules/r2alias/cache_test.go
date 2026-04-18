package r2alias

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// TestCache_HitAfterMiss asserts a first call invokes fetchFn; a second call
// within TTL does not.
func TestCache_HitAfterMiss(t *testing.T) {
	c := newAliasCache(10, 1*time.Second)
	var calls int32
	fetch := func(_ context.Context, _ string) (aliasEntry, error) {
		atomic.AddInt32(&calls, 1)
		return aliasEntry{DeployID: "d1", Present: true}, nil
	}

	e1, err := c.Resolve(context.Background(), "b", "site-a", "production", fetch)
	if err != nil {
		t.Fatalf("first Resolve: unexpected error: %v", err)
	}
	if e1.DeployID != "d1" || !e1.Present {
		t.Fatalf("first Resolve returned wrong entry: %+v", e1)
	}

	e2, err := c.Resolve(context.Background(), "b", "site-a", "production", fetch)
	if err != nil {
		t.Fatalf("second Resolve: unexpected error: %v", err)
	}
	if e2 != e1 {
		t.Fatalf("second Resolve should return cached entry %+v, got %+v", e1, e2)
	}
	if got := atomic.LoadInt32(&calls); got != 1 {
		t.Fatalf("fetchFn should run exactly once, ran %d times", got)
	}
}

// TestCache_TTLExpiry asserts a second call AFTER TTL invokes fetchFn again.
func TestCache_TTLExpiry(t *testing.T) {
	c := newAliasCache(10, 50*time.Millisecond)
	var calls int32
	fetch := func(_ context.Context, _ string) (aliasEntry, error) {
		atomic.AddInt32(&calls, 1)
		return aliasEntry{DeployID: "d1", Present: true}, nil
	}

	if _, err := c.Resolve(context.Background(), "b", "site-a", "production", fetch); err != nil {
		t.Fatalf("first Resolve: %v", err)
	}
	time.Sleep(80 * time.Millisecond) // past TTL
	if _, err := c.Resolve(context.Background(), "b", "site-a", "production", fetch); err != nil {
		t.Fatalf("post-TTL Resolve: %v", err)
	}
	if got := atomic.LoadInt32(&calls); got != 2 {
		t.Fatalf("fetchFn should run twice (before + after TTL), ran %d times", got)
	}
}

// TestCache_LRUEvictionAtCapacity asserts LRU evicts the oldest entry on overflow.
func TestCache_LRUEvictionAtCapacity(t *testing.T) {
	c := newAliasCache(3, 10*time.Second)
	var mu sync.Mutex
	fetchLog := []string{}

	fetch := func(_ context.Context, key string) (aliasEntry, error) {
		mu.Lock()
		defer mu.Unlock()
		fetchLog = append(fetchLog, key)
		return aliasEntry{DeployID: "d-" + key, Present: true}, nil
	}

	ctx := context.Background()
	// Fill with 3 distinct keys
	for i := 1; i <= 3; i++ {
		if _, err := c.Resolve(ctx, "b", fmt.Sprintf("site-%d", i), "production", fetch); err != nil {
			t.Fatalf("Resolve site-%d: %v", i, err)
		}
	}
	// Insert 4th distinct key — evicts site-1 (oldest)
	if _, err := c.Resolve(ctx, "b", "site-4", "production", fetch); err != nil {
		t.Fatalf("Resolve site-4: %v", err)
	}
	// Re-resolve site-1 — should re-fetch (evicted)
	if _, err := c.Resolve(ctx, "b", "site-1", "production", fetch); err != nil {
		t.Fatalf("Resolve site-1 after eviction: %v", err)
	}

	mu.Lock()
	defer mu.Unlock()
	// fetchLog should be: site-1, site-2, site-3, site-4, site-1 (re-fetch)
	if len(fetchLog) != 5 {
		t.Fatalf("expected 5 fetches (3 initial + 1 new + 1 re-fetch after eviction), got %d: %v",
			len(fetchLog), fetchLog)
	}
	if fetchLog[4] != "b/site-1/production" {
		t.Fatalf("last fetch should be site-1 re-fetch, got %q", fetchLog[4])
	}
}

// TestCache_MissingSentinelCached asserts Present=false entries are cached
// for the full TTL (not re-fetched on the next call).
func TestCache_MissingSentinelCached(t *testing.T) {
	c := newAliasCache(10, 1*time.Second)
	var calls int32
	fetch := func(_ context.Context, _ string) (aliasEntry, error) {
		atomic.AddInt32(&calls, 1)
		return aliasEntry{Present: false}, nil
	}

	e1, err := c.Resolve(context.Background(), "b", "dead-site", "production", fetch)
	if err != nil {
		t.Fatalf("first Resolve: %v", err)
	}
	if e1.Present {
		t.Fatalf("first Resolve should return Present=false, got %+v", e1)
	}
	// Second Resolve — cached sentinel, no re-fetch
	e2, err := c.Resolve(context.Background(), "b", "dead-site", "production", fetch)
	if err != nil {
		t.Fatalf("second Resolve: %v", err)
	}
	if e2.Present {
		t.Fatalf("cached sentinel should be Present=false, got %+v", e2)
	}
	if got := atomic.LoadInt32(&calls); got != 1 {
		t.Fatalf("missing-sentinel should cache: fetchFn ran %d times (want 1)", got)
	}
}

// TestCache_Singleflight asserts N concurrent calls for the same key produce
// exactly ONE fetchFn invocation (stampede protection).
func TestCache_Singleflight(t *testing.T) {
	const concurrency = 1000
	c := newAliasCache(10, 1*time.Second)

	var calls int32
	fetch := func(_ context.Context, _ string) (aliasEntry, error) {
		atomic.AddInt32(&calls, 1)
		time.Sleep(200 * time.Millisecond) // keep the flight window open
		return aliasEntry{DeployID: "d1", Present: true}, nil
	}

	var wg sync.WaitGroup
	wg.Add(concurrency)
	start := make(chan struct{})
	for i := 0; i < concurrency; i++ {
		go func() {
			defer wg.Done()
			<-start
			_, _ = c.Resolve(context.Background(), "b", "site-a", "production", fetch)
		}()
	}
	close(start) // release all goroutines
	wg.Wait()

	if got := atomic.LoadInt32(&calls); got != 1 {
		t.Fatalf("singleflight should coalesce %d concurrent calls into 1, got %d", concurrency, got)
	}
}

// TestCache_ErrorNotCached asserts a fetchFn error is NOT stored — the next
// call must retry. Sticky errors would amplify outages.
func TestCache_ErrorNotCached(t *testing.T) {
	c := newAliasCache(10, 1*time.Second)
	var calls int32
	testErr := errors.New("transient r2 failure")

	fetch := func(_ context.Context, _ string) (aliasEntry, error) {
		n := atomic.AddInt32(&calls, 1)
		if n == 1 {
			return aliasEntry{}, testErr
		}
		return aliasEntry{DeployID: "d1", Present: true}, nil
	}

	if _, err := c.Resolve(context.Background(), "b", "site-a", "production", fetch); !errors.Is(err, testErr) {
		t.Fatalf("first Resolve should return testErr, got %v", err)
	}
	e2, err := c.Resolve(context.Background(), "b", "site-a", "production", fetch)
	if err != nil {
		t.Fatalf("second Resolve should succeed (error not sticky), got %v", err)
	}
	if e2.DeployID != "d1" || !e2.Present {
		t.Fatalf("second Resolve returned wrong entry: %+v", e2)
	}
	if got := atomic.LoadInt32(&calls); got != 2 {
		t.Fatalf("fetchFn should run twice (error then success), ran %d", got)
	}
}

// TestCache_KeyComposition asserts the composed key is `bucket/site/aliasName`
// so different tuples do not collide.
func TestCache_KeyComposition(t *testing.T) {
	c := newAliasCache(10, 1*time.Second)
	var mu sync.Mutex
	seen := map[string]struct{}{}

	fetch := func(_ context.Context, key string) (aliasEntry, error) {
		mu.Lock()
		defer mu.Unlock()
		seen[key] = struct{}{}
		return aliasEntry{DeployID: "d-" + key, Present: true}, nil
	}

	ctx := context.Background()
	_, _ = c.Resolve(ctx, "b1", "site-a", "production", fetch)
	_, _ = c.Resolve(ctx, "b2", "site-a", "production", fetch) // different bucket
	_, _ = c.Resolve(ctx, "b1", "site-b", "production", fetch) // different site
	_, _ = c.Resolve(ctx, "b1", "site-a", "preview", fetch)    // different alias

	mu.Lock()
	defer mu.Unlock()
	want := map[string]struct{}{
		"b1/site-a/production": {},
		"b2/site-a/production": {},
		"b1/site-b/production": {},
		"b1/site-a/preview":    {},
	}
	if len(seen) != len(want) {
		t.Fatalf("expected %d distinct cache keys, got %d: %v", len(want), len(seen), seen)
	}
	for k := range want {
		if _, ok := seen[k]; !ok {
			t.Errorf("missing expected key: %q", k)
		}
	}
}
