package r2alias

import (
	"context"
	"errors"
	"io/fs"
	"net/http"
	"strings"
	"testing"
	"time"

	awshttp "github.com/aws/aws-sdk-go-v2/aws/transport/http"
	"github.com/aws/smithy-go/logging"
	smithyhttp "github.com/aws/smithy-go/transport/http"
	"github.com/caddyserver/caddy/v2"
	"github.com/prometheus/client_golang/prometheus/testutil"
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
	"go.uber.org/zap/zaptest/observer"
	"golang.org/x/sync/semaphore"
)

func TestResolvePlaceholders_ResolvesEnvAtProvision(t *testing.T) {
	t.Setenv("R2ALIAS_TEST_BUCKET", "universe-static-apps-01")

	bucket := "{env.R2ALIAS_TEST_BUCKET}"
	if err := resolvePlaceholders(map[string]*string{"bucket": &bucket}); err != nil {
		t.Fatalf("resolvePlaceholders: %v", err)
	}
	if bucket != "universe-static-apps-01" {
		t.Errorf("bucket: want the env value, got %q", bucket)
	}
}

func TestResolvePlaceholders_FailsOnAnEmptyEnvVar(t *testing.T) {
	t.Setenv("R2ALIAS_TEST_EMPTY", "")

	secret := "{env.R2ALIAS_TEST_EMPTY}"
	if err := resolvePlaceholders(map[string]*string{"secret_access_key": &secret}); err == nil {
		t.Fatal("an unset credential must fail the load, not sign with an empty key")
	}
}

func TestResolvePlaceholders_LeavesAPlainValueAlone(t *testing.T) {
	value := "universe-static-apps-01"
	if err := resolvePlaceholders(map[string]*string{"endpoint": &value}); err != nil {
		t.Fatalf("resolvePlaceholders: %v", err)
	}
	if value != "universe-static-apps-01" {
		t.Errorf("value: want it untouched, got %q", value)
	}
}

func TestResolvePlaceholders_RejectsARegexQuantifier(t *testing.T) {
	pattern := defaultDeployIDRegex
	if err := resolvePlaceholders(map[string]*string{"deploy_id_regex": &pattern}); err == nil {
		t.Fatal("a regex quantifier reads as a placeholder, which is why Provision must never pass one")
	}
}

func TestSharedS3Client_ReusesOneClientPerConfig(t *testing.T) {
	ctx := caddy.Context{Context: context.Background()}
	cfg := r2ClientConfig{
		Bucket:      "b",
		Endpoint:    "https://r2.example",
		Region:      "auto",
		AccessKeyID: "kid", SecretAccessKey: "sak",
		UsePathStyle: true,
		MaxAttempts:  2,
		MaxBackoff:   time.Second,
	}

	first, firstKey, err := sharedS3Client(ctx, cfg, zap.NewNop())
	if err != nil {
		t.Fatalf("sharedS3Client: %v", err)
	}
	t.Cleanup(func() { _, _ = s3Clients.Delete(firstKey) })

	second, secondKey, err := sharedS3Client(ctx, cfg, zap.NewNop())
	if err != nil {
		t.Fatalf("sharedS3Client: %v", err)
	}
	t.Cleanup(func() { _, _ = s3Clients.Delete(secondKey) })

	if first != second {
		t.Error("one config must yield one client, so a reload does not leak a connection pool")
	}
	if firstKey != secondKey {
		t.Errorf("pool keys diverged: %q and %q", firstKey, secondKey)
	}

	other := cfg
	other.Endpoint = "https://other.example"
	third, thirdKey, err := sharedS3Client(ctx, other, zap.NewNop())
	if err != nil {
		t.Fatalf("sharedS3Client: %v", err)
	}
	t.Cleanup(func() { _, _ = s3Clients.Delete(thirdKey) })
	if third == first {
		t.Error("a different endpoint must not share a client")
	}
}

func TestSharedAliasCache_KeysOnTheEndpoint(t *testing.T) {
	first, firstKey := sharedAliasCache(r2ClientConfig{Endpoint: "https://a.example", Bucket: "b"}, 10, time.Second, time.Second)
	t.Cleanup(func() { _, _ = aliasCaches.Delete(firstKey) })
	second, secondKey := sharedAliasCache(r2ClientConfig{Endpoint: "https://b.example", Bucket: "b"}, 10, time.Second, time.Second)
	t.Cleanup(func() { _, _ = aliasCaches.Delete(secondKey) })

	if first == second {
		t.Error("two endpoints with one bucket name must not share an alias cache")
	}
}

func TestR2FS_AcquireBudget_RefusesBeyondTheCap(t *testing.T) {
	r := newTestR2FS()
	r.budget = semaphore.NewWeighted(16)

	if err := r.acquireBudget(context.Background(), 16); err != nil {
		t.Fatalf("the first acquisition must fit: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	err := r.acquireBudget(ctx, 16)
	if err == nil {
		t.Fatal("a full budget must refuse the next body rather than grow the heap")
	}
	if !strings.Contains(err.Error(), "in-flight budget exhausted") {
		t.Errorf("error should name the budget, got %v", err)
	}

	r.releaseBudget(16)
	if err := r.acquireBudget(context.Background(), 16); err != nil {
		t.Fatalf("Close must return the budget: %v", err)
	}
}

func TestR2FS_CloseReturnsTheBudget(t *testing.T) {
	body := []byte("body")
	r := newTestR2FS()
	r.budget = semaphore.NewWeighted(int64(len(body)))
	r.header = stubFSFetcher(&r2Object{Size: int64(len(body))}, nil)
	r.fetcher = stubFSFetcher(&r2Object{Body: body}, nil)

	file, err := r.Open("site/deploys/v1/index.html")
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	if _, err := file.Read(make([]byte, len(body))); err != nil {
		t.Fatalf("Read: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	if err := r.acquireBudget(ctx, int64(len(body))); err == nil {
		t.Fatal("an open file must hold its budget")
	}

	if err := file.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	if err := r.acquireBudget(context.Background(), int64(len(body))); err != nil {
		t.Fatalf("Close must release the budget: %v", err)
	}
}

func TestR2FS_OpenAndStatAgreeOnErrorShape(t *testing.T) {
	cases := []struct {
		name          string
		headerErr     error
		probe         func(context.Context, string) (bool, error)
		wantNotExist  bool
		wantPathError bool
	}{
		{
			name:          "missing object",
			headerErr:     fs.ErrNotExist,
			probe:         stubIndexProbe(false, nil),
			wantNotExist:  true,
			wantPathError: true,
		},
		{
			name:          "upstream failure",
			headerErr:     errors.New("caddy.fs.r2: upstream 503"),
			probe:         stubIndexProbe(false, nil),
			wantNotExist:  false,
			wantPathError: false,
		},
		{
			name:          "probe failure",
			headerErr:     fs.ErrNotExist,
			probe:         stubIndexProbe(false, errors.New("caddy.fs.r2: upstream 503")),
			wantNotExist:  false,
			wantPathError: false,
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			r := newTestR2FS()
			r.header = stubFSFetcher(nil, c.headerErr)
			r.indexProbe = c.probe

			_, openErr := r.Open("site/deploys/v1/index.html")
			_, statErr := r.Stat("site/deploys/v1/index.html")
			if openErr == nil || statErr == nil {
				t.Fatalf("both must fail: open=%v stat=%v", openErr, statErr)
			}

			for label, err := range map[string]error{"Open": openErr, "Stat": statErr} {
				if got := errors.Is(err, fs.ErrNotExist); got != c.wantNotExist {
					t.Errorf("%s ErrNotExist: want %v, got %v (%v)", label, c.wantNotExist, got, err)
				}
				var pe *fs.PathError
				if got := errors.As(err, &pe); got != c.wantPathError {
					t.Errorf("%s PathError: want %v, got %v (%v)", label, c.wantPathError, got, err)
				}
			}
		})
	}
}

func TestMetrics_CountR2OperationsAndLookups(t *testing.T) {
	initMetrics(nil)

	before := testutil.ToFloat64(moduleMetrics.operations.WithLabelValues(opGet, resultNotFound))

	r := newWiredR2FS(t, writeNoSuchKey)
	if _, err := r.getObject(context.Background(), "site/missing.html"); !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("want fs.ErrNotExist, got %v", err)
	}

	after := testutil.ToFloat64(moduleMetrics.operations.WithLabelValues(opGet, resultNotFound))
	if after != before+1 {
		t.Errorf("a missing object must count once: before %v, after %v", before, after)
	}
}

func TestMetrics_CountAliasCacheOutcomes(t *testing.T) {
	initMetrics(nil)

	beforeMiss := testutil.ToFloat64(moduleMetrics.lookups.WithLabelValues(resultMiss))
	beforeHit := testutil.ToFloat64(moduleMetrics.lookups.WithLabelValues(resultHit))

	cache := newAliasCache(4, time.Minute, time.Second)
	fetch := func(context.Context, string) (aliasEntry, error) {
		return aliasEntry{DeployID: "v1", Present: true}, nil
	}
	for range 2 {
		if _, err := cache.Resolve(context.Background(), "b", "site", "production", fetch); err != nil {
			t.Fatalf("Resolve: %v", err)
		}
	}

	if got := testutil.ToFloat64(moduleMetrics.lookups.WithLabelValues(resultMiss)); got != beforeMiss+1 {
		t.Errorf("miss count: want %v, got %v", beforeMiss+1, got)
	}
	if got := testutil.ToFloat64(moduleMetrics.lookups.WithLabelValues(resultHit)); got != beforeHit+1 {
		t.Errorf("hit count: want %v, got %v", beforeHit+1, got)
	}
}

func TestUpstreamStatus_TreatsThrottlingAsUpstream(t *testing.T) {
	r := newWiredR2FS(t, func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Retry-After", "7")
		w.WriteHeader(http.StatusTooManyRequests)
	})

	_, err := r.getObject(context.Background(), "site/index.html")
	if err == nil {
		t.Fatal("a throttled fetch must fail")
	}
	if code, upstream := upstreamStatus(err); !upstream || code != http.StatusTooManyRequests {
		t.Errorf("429 must classify as upstream, got code=%d upstream=%v (%v)", code, upstream, err)
	}
	if got := retryAfterFrom(err); got != "7" {
		t.Errorf("Retry-After: want R2's own 7, got %q", got)
	}
}

func TestSDKLogger_BridgesToZap(t *testing.T) {
	core, logs := observer.New(zapcore.DebugLevel)
	bridge := sdkLogger{logger: zap.New(core)}

	bridge.Logf(logging.Warn, "checksum %s skipped", "sha256")
	bridge.Logf(logging.Debug, "attempt %d", 2)

	entries := logs.All()
	if len(entries) != 2 {
		t.Fatalf("want 2 structured entries, got %d", len(entries))
	}
	if entries[0].Level != zapcore.WarnLevel {
		t.Errorf("an SDK warning must arrive as a warning, got %v", entries[0].Level)
	}
	if got := entries[0].ContextMap()["message"]; got != "checksum sha256 skipped" {
		t.Errorf("message: got %v", got)
	}
	if entries[1].Level != zapcore.DebugLevel {
		t.Errorf("SDK chatter must arrive as debug, got %v", entries[1].Level)
	}
}

func TestSDKLogger_ToleratesNoLogger(t *testing.T) {
	sdkLogger{}.Logf(logging.Warn, "no logger wired yet")
}

func TestCleanup_ReleasesPooledResources(t *testing.T) {
	ctx := caddy.Context{Context: context.Background()}
	cfg := r2ClientConfig{
		Bucket: "cleanup", Endpoint: "https://cleanup.example", Region: "auto",
		AccessKeyID: "kid", SecretAccessKey: "sak",
		UsePathStyle: true, MaxAttempts: 2, MaxBackoff: time.Second,
	}
	client, clientKey, err := sharedS3Client(ctx, cfg, zap.NewNop())
	if err != nil {
		t.Fatalf("sharedS3Client: %v", err)
	}
	cache, cacheKey := sharedAliasCache(cfg, 4, time.Minute, time.Second)

	alias := &R2Alias{client: client, clientKey: clientKey, cache: cache, cacheKey: cacheKey}
	if err := alias.Cleanup(); err != nil {
		t.Fatalf("Cleanup: %v", err)
	}

	fs := &R2FS{clientKey: clientKey}
	if err := fs.Cleanup(); err != nil {
		t.Fatalf("Cleanup with a released key: %v", err)
	}
	if err := (&R2FS{}).Cleanup(); err != nil {
		t.Fatalf("Cleanup before Provision must be a no-op: %v", err)
	}
}

func TestR2FS_Validate_RequiresBucketAndEndpoint(t *testing.T) {
	if err := (&R2FS{Endpoint: "https://r2.example"}).Validate(); err == nil {
		t.Error("bucket is required")
	}
	if err := (&R2FS{Bucket: "b"}).Validate(); err == nil {
		t.Error("endpoint is required")
	}

	tooSmall := &R2FS{
		Bucket: "b", Endpoint: "https://r2.example",
		MaxFileSize: 100, MaxInFlightBytes: 1,
	}
	if err := tooSmall.Validate(); err == nil {
		t.Error("a budget below one object must be rejected, not silently widened")
	}

	valid := &R2FS{Bucket: "b", Endpoint: "https://r2.example"}
	if err := valid.Validate(); err != nil {
		t.Fatalf("Validate: %v", err)
	}
	if valid.UsePathStyle == nil || !*valid.UsePathStyle {
		t.Error("R2 needs path-style addressing by default")
	}
	if valid.MaxInFlightBytes < valid.MaxFileSize {
		t.Errorf("the default budget %d must hold at least one object of %d",
			valid.MaxInFlightBytes, valid.MaxFileSize)
	}
}

func TestR2FS_ReweighBudget_ChargesTheDeliveredBody(t *testing.T) {
	r := newTestR2FS()
	r.budget = semaphore.NewWeighted(64)

	if err := r.acquireBudget(context.Background(), 16); err != nil {
		t.Fatalf("acquire: %v", err)
	}
	held, err := r.reweighBudget(16, 64)
	if err != nil {
		t.Fatalf("reweigh up: %v", err)
	}
	if held != 64 {
		t.Errorf("held: want the delivered 64, got %d", held)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	if err := r.acquireBudget(ctx, 1); err == nil {
		t.Fatal("a body larger than its HeadObject size must still be charged in full")
	}

	r.releaseBudget(held)
	if err := r.acquireBudget(context.Background(), 64); err != nil {
		t.Fatalf("the full budget must return: %v", err)
	}
	r.releaseBudget(64)

	if err := r.acquireBudget(context.Background(), 64); err != nil {
		t.Fatalf("acquire: %v", err)
	}
	held, err = r.reweighBudget(64, 8)
	if err != nil {
		t.Fatalf("reweigh down: %v", err)
	}
	if held != 8 {
		t.Errorf("held: want the delivered 8, got %d", held)
	}
	if err := r.acquireBudget(context.Background(), 56); err != nil {
		t.Fatalf("a smaller body must hand the surplus back: %v", err)
	}
}

func TestR2FS_ReweighBudget_NeverStallsOnAContendedBudget(t *testing.T) {
	r := newTestR2FS()
	r.budget = semaphore.NewWeighted(64)

	for range 2 {
		if err := r.acquireBudget(context.Background(), 32); err != nil {
			t.Fatalf("acquire: %v", err)
		}
	}

	start := time.Now()
	results := make(chan int64, 2)
	for range 2 {
		go func() {
			held, _ := r.reweighBudget(32, 64)
			results <- held
		}()
	}
	for range 2 {
		if held := <-results; held > 0 {
			r.releaseBudget(held)
		}
	}
	if elapsed := time.Since(start); elapsed > time.Second {
		t.Fatalf("two concurrent reweigh-ups must not stall on each other, took %s", elapsed)
	}

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if err := r.acquireBudget(ctx, 64); err != nil {
		t.Fatalf("every charge must be accounted for once the reweighs settle: %v", err)
	}
}

func TestR2FS_ReweighBudget_ShrinkSucceedsWhileAWaiterIsQueued(t *testing.T) {
	r := newTestR2FS()
	r.budget = semaphore.NewWeighted(64)

	if err := r.acquireBudget(context.Background(), 8); err != nil {
		t.Fatalf("our own charge: %v", err)
	}
	if err := r.acquireBudget(context.Background(), 40); err != nil {
		t.Fatalf("another request's charge: %v", err)
	}

	waiterCtx, cancelWaiter := context.WithCancel(context.Background())
	defer cancelWaiter()
	go func() { _ = r.budget.Acquire(waiterCtx, 32) }()
	for r.budget.TryAcquire(1) {
		r.budget.Release(1)
	}

	held, err := r.reweighBudget(8, 4)
	if err != nil {
		t.Fatalf("a shrink returns capacity and must never fail, even behind a queued waiter: %v", err)
	}
	if held != 4 {
		t.Errorf("held: want 4, got %d", held)
	}
}

func TestNewBudgetedRetryer_RetriesThrottling(t *testing.T) {
	retryer := newBudgetedRetryer(2, time.Second)

	throttled := &awshttp.ResponseError{
		ResponseError: &smithyhttp.ResponseError{
			Response: &smithyhttp.Response{
				Response: &http.Response{StatusCode: http.StatusTooManyRequests},
			},
			Err: errors.New("TooManyRequests"),
		},
	}
	if !retryer.IsErrorRetryable(throttled) {
		t.Error("R2 throttling must be retryable; the SDK default set stops at 504")
	}

	serverError := &awshttp.ResponseError{
		ResponseError: &smithyhttp.ResponseError{
			Response: &smithyhttp.Response{
				Response: &http.Response{StatusCode: http.StatusServiceUnavailable},
			},
			Err: errors.New("ServiceUnavailable"),
		},
	}
	if !retryer.IsErrorRetryable(serverError) {
		t.Error("a 503 must stay retryable")
	}

	notFound := &awshttp.ResponseError{
		ResponseError: &smithyhttp.ResponseError{
			Response: &smithyhttp.Response{
				Response: &http.Response{StatusCode: http.StatusNotFound},
			},
			Err: errors.New("NoSuchKey"),
		},
	}
	if retryer.IsErrorRetryable(notFound) {
		t.Error("a missing key must not be retried")
	}
	if got := retryer.MaxAttempts(); got != 2 {
		t.Errorf("MaxAttempts: want 2, got %d", got)
	}
}
