package r2alias

import (
	"context"
	"errors"
	"io/fs"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func countingHead(obj *r2Object, err error, calls *atomic.Int32) func(context.Context) (*r2Object, error) {
	return func(context.Context) (*r2Object, error) {
		calls.Add(1)
		return obj, err
	}
}

func TestHeadCache_RepeatsAPositiveAnswerWithoutAFetch(t *testing.T) {
	t.Parallel()
	var calls atomic.Int32
	c := newHeadCache(16, time.Hour)
	fetch := countingHead(&r2Object{Size: 7, ContentType: "text/html"}, nil, &calls)

	first, err := c.Resolve(context.Background(), "b/k", fetch)
	if err != nil {
		t.Fatalf("first: %v", err)
	}
	second, err := c.Resolve(context.Background(), "b/k", fetch)
	if err != nil {
		t.Fatalf("second: %v", err)
	}
	if calls.Load() != 1 {
		t.Fatalf("fetches: want 1, got %d", calls.Load())
	}
	if first.Size != 7 || second.Size != 7 || second.ContentType != "text/html" {
		t.Fatalf("cached metadata lost: %+v %+v", first, second)
	}
}

func TestHeadCache_RepeatsANotExistAnswerWithoutAFetch(t *testing.T) {
	t.Parallel()
	var calls atomic.Int32
	c := newHeadCache(16, time.Hour)
	fetch := countingHead(nil, fs.ErrNotExist, &calls)

	for i := 0; i < 3; i++ {
		if _, err := c.Resolve(context.Background(), "b/missing", fetch); !errors.Is(err, fs.ErrNotExist) {
			t.Fatalf("call %d: want ErrNotExist, got %v", i, err)
		}
	}
	if calls.Load() != 1 {
		t.Fatalf("fetches for a missing key: want 1, got %d", calls.Load())
	}
}

func TestHeadCache_NeverCachesAnUpstreamError(t *testing.T) {
	t.Parallel()
	var calls atomic.Int32
	c := newHeadCache(16, time.Hour)
	fetch := countingHead(nil, errors.New("upstream 503"), &calls)

	for i := 0; i < 3; i++ {
		if _, err := c.Resolve(context.Background(), "b/k", fetch); err == nil {
			t.Fatal("want the upstream error")
		}
	}
	if calls.Load() != 3 {
		t.Fatalf("an error must be retried every time: want 3 fetches, got %d", calls.Load())
	}
}

func TestHeadCache_ExpiresAfterTTL(t *testing.T) {
	t.Parallel()
	var calls atomic.Int32
	c := newHeadCache(16, 50*time.Millisecond)
	fetch := countingHead(nil, fs.ErrNotExist, &calls)

	_, _ = c.Resolve(context.Background(), "b/k", fetch)
	time.Sleep(120 * time.Millisecond)
	_, _ = c.Resolve(context.Background(), "b/k", fetch)
	if calls.Load() != 2 {
		t.Fatalf("fetches across the TTL: want 2, got %d", calls.Load())
	}
}

func TestHeadCache_CoalescesConcurrentMisses(t *testing.T) {
	t.Parallel()
	var calls atomic.Int32
	c := newHeadCache(16, time.Hour)
	fetch := func(context.Context) (*r2Object, error) {
		calls.Add(1)
		time.Sleep(30 * time.Millisecond)
		return &r2Object{Size: 1}, nil
	}
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, err := c.Resolve(context.Background(), "b/k", fetch); err != nil {
				t.Errorf("resolve: %v", err)
			}
		}()
	}
	wg.Wait()
	if calls.Load() != 1 {
		t.Fatalf("concurrent misses: want 1 fetch, got %d", calls.Load())
	}
}

func TestHeadCache_StoreSeedsAPositiveAnswer(t *testing.T) {
	t.Parallel()
	var calls atomic.Int32
	c := newHeadCache(16, time.Hour)
	c.Store("b/k", &r2Object{Size: 9, ContentType: "text/css"})

	obj, err := c.Resolve(context.Background(), "b/k", countingHead(nil, fs.ErrNotExist, &calls))
	if err != nil || obj.Size != 9 {
		t.Fatalf("seeded entry not served: obj=%+v err=%v", obj, err)
	}
	if calls.Load() != 0 {
		t.Fatalf("a seeded key must not fetch, got %d", calls.Load())
	}
}
