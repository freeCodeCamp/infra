package r2alias_test

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/caddyserver/caddy/v2/caddytest"

	_ "github.com/freeCodeCamp-Universe/infra/caddy-r2alias"
)

const testBucket = "gxy-cassiopeia-test"

// rootDomain is test-only so production config is never a live target here.
const rootDomain = "test.camp"

// cacheTTL is short enough that TestIntegration_AliasFlip can wait past it
// without slowing the suite.
const cacheTTL = 500 * time.Millisecond

// caddyAdminPort / caddyHTTPPort keep the in-process Caddy off the real
// Caddy defaults so a developer running Caddy locally doesn't collide.
const (
	caddyAdminPort = 2999
	caddyHTTPPort  = 9080
	caddyHTTPSPort = 9443
)

const (
	documentCacheControl  = "public, max-age=0, must-revalidate"
	errorCacheControl     = "no-store"
	chartMaxFileSize      = "33554432"
	chartMetricsPort      = "9180"
	chartMaxInFlightBytes = "100663296"
)

// The disk layout is independent of the S3 prefix so one fixture set can back
// multiple site names.
func uploadDeployFixtures(t *testing.T, stub *s3Stub, site, version string) {
	t.Helper()

	srcDir := filepath.Join("testdata", "site-a", "deploys", version)
	err := filepath.Walk(srcDir, func(path string, info os.FileInfo, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if info.IsDir() {
			return nil
		}
		rel := strings.TrimPrefix(filepath.ToSlash(path), filepath.ToSlash(srcDir)+"/")

		body, readErr := os.ReadFile(path)
		if readErr != nil {
			return readErr
		}
		stub.put(fmt.Sprintf("%s/deploys/%s/%s", site, version, rel), string(body), "text/html")
		return nil
	})
	if err != nil {
		t.Fatalf("upload fixtures %s/%s: %v", site, version, err)
	}
}

func startCaddy(t *testing.T, s3Endpoint string) *caddytest.Tester {
	t.Helper()
	return startCaddyWithMaxFileSize(t, s3Endpoint, 0)
}

func startCaddyWithMaxFileSize(t *testing.T, s3Endpoint string, maxFileSize int64) *caddytest.Tester {
	t.Helper()
	sizeDirective := ""
	if maxFileSize > 0 {
		sizeDirective = fmt.Sprintf("max_file_size %d", maxFileSize)
	}
	caddyfile := fmt.Sprintf(`
{
	admin localhost:%d
	http_port %d
	https_port %d
	auto_https off
	grace_period 1ns

	order r2_alias before file_server

	filesystem r2 r2 {
		bucket %s
		endpoint %s
		region us-east-1
		access_key_id test
		secret_access_key test
		use_path_style
		%s
	}
}

:%d {
	handle {
		header Cache-Control "%s"

		r2_alias {
			bucket %s
			endpoint %s
			region us-east-1
			access_key_id test
			secret_access_key test
			cache_ttl %s
			fetch_timeout 2s
			root_domain %s
		}
		file_server {
			fs r2
		}
	}

	handle_errors {
		header Cache-Control "%s"
		header -Etag

		@404 expression {err.status_code} == 404
		respond @404 "Not Found" 404

		@400 expression {err.status_code} == 400
		respond @400 "Bad Request" 400

		@405 expression {err.status_code} == 405
		respond @405 "Method Not Allowed" 405

		@503 expression {err.status_code} == 503
		respond @503 "Service Unavailable" 503

		respond "Server Error" 500
	}
}
`,
		caddyAdminPort, caddyHTTPPort, caddyHTTPSPort,
		testBucket, s3Endpoint, sizeDirective,
		caddyHTTPPort,
		documentCacheControl,
		testBucket, s3Endpoint,
		cacheTTL, rootDomain,
		errorCacheControl,
	)
	tester := caddytest.NewTester(t)
	tester.InitServer(caddyfile, "caddyfile")
	return tester
}

// doGet issues an HTTP GET with a virtual Host header and returns status + body.
// The TCP target is always the caddytest HTTP listener on localhost.
func doGet(t *testing.T, tester *caddytest.Tester, host, path string) (int, string) {
	t.Helper()
	resp, body := doGetResponse(t, tester, host, path)
	return resp.StatusCode, body
}

// doGetResponse is doGet for a test that asserts on transport details. The body
// is already drained and closed; read it from the returned string, not resp.Body.
func doGetResponse(t *testing.T, tester *caddytest.Tester, host, path string) (*http.Response, string) {
	t.Helper()
	url := fmt.Sprintf("http://localhost:%d%s", caddyHTTPPort, path)
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	req.Host = host

	resp, err := tester.Client.Do(req)
	if err != nil {
		t.Fatalf("GET %s (Host=%s): %v", url, host, err)
	}
	defer func() { _ = resp.Body.Close() }()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read body: %v", err)
	}
	return resp, string(body)
}

// assertBodyContains checks substring inclusion so tests survive formatter
// reflows of the HTML fixtures.
func assertBodyContains(t *testing.T, body, want string) {
	t.Helper()
	if !strings.Contains(body, want) {
		t.Fatalf("body mismatch: want substring %q, got %q", want, body)
	}
}

func TestIntegration_ResolveProduction(t *testing.T) {
	stub := startS3Stub(t)
	site := "site-a." + rootDomain

	uploadDeployFixtures(t, stub, site, "v1")
	stub.putAlias(site, "production", "v1")

	tester := startCaddy(t, stub.endpoint())

	status, body := doGet(t, tester, site, "/")
	if status != http.StatusOK {
		t.Fatalf("status: want 200, got %d (body=%q)", status, body)
	}
	assertBodyContains(t, body, "V1")
}

func TestIntegration_AliasFlip(t *testing.T) {
	stub := startS3Stub(t)
	site := "site-a." + rootDomain

	uploadDeployFixtures(t, stub, site, "v1")
	uploadDeployFixtures(t, stub, site, "v2")
	stub.putAlias(site, "production", "v1")

	tester := startCaddy(t, stub.endpoint())

	status, body := doGet(t, tester, site, "/")
	if status != http.StatusOK {
		t.Fatalf("pre-flip status: want 200, got %d (body=%q)", status, body)
	}
	assertBodyContains(t, body, "V1")

	stub.putAlias(site, "production", "v2")

	// Poll past the cache TTL — CI timing jitter makes a single post-TTL
	// sleep brittle. 5s is generous relative to the 500ms TTL.
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		status, body = doGet(t, tester, site, "/")
		if status == http.StatusOK && strings.Contains(body, "V2") {
			return
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatalf("post-flip never served V2 within 5s: last status=%d body=%q", status, body)
}

func TestIntegration_PreviewRouting(t *testing.T) {
	stub := startS3Stub(t)
	prodSite := "site-a." + rootDomain
	previewHost := "site-a.preview." + rootDomain

	uploadDeployFixtures(t, stub, prodSite, "v2")
	stub.putAlias(prodSite, "preview", "v2")

	tester := startCaddy(t, stub.endpoint())

	status, body := doGet(t, tester, previewHost, "/")
	if status != http.StatusOK {
		t.Fatalf("status: want 200, got %d (body=%q)", status, body)
	}
	assertBodyContains(t, body, "V2")
}

func TestIntegration_DottedDirectoryServesIndex(t *testing.T) {
	stub := startS3Stub(t)
	site := "site-a." + rootDomain

	uploadDeployFixtures(t, stub, site, "v1")
	stub.putAlias(site, "production", "v1")
	stub.put(site+"/deploys/v1/assets.min/index.html", "<h1>MINIFIED</h1>", "text/html")

	tester := startCaddy(t, stub.endpoint())

	status, body := doGet(t, tester, site, "/assets.min/")
	if status != http.StatusOK {
		t.Fatalf("status: want 200, got %d (body=%q)", status, body)
	}
	assertBodyContains(t, body, "MINIFIED")
}

func TestIntegration_DottedDeployIDServesRoot(t *testing.T) {
	stub := startS3Stub(t)
	site := "site-a." + rootDomain

	stub.put(site+"/deploys/v1.2.3/index.html", "<h1>V1.2.3</h1>", "text/html")
	stub.putAlias(site, "production", "v1.2.3")

	tester := startCaddy(t, stub.endpoint())

	status, body := doGet(t, tester, site, "/")
	if status != http.StatusOK {
		t.Fatalf("status: want 200, got %d (body=%q)", status, body)
	}
	assertBodyContains(t, body, "V1.2.3")
}

func TestIntegration_ServesIndexWithOneBodyFetch(t *testing.T) {
	stub := startS3Stub(t)
	site := "site-a." + rootDomain

	uploadDeployFixtures(t, stub, site, "v1")
	stub.putAlias(site, "production", "v1")

	tester := startCaddy(t, stub.endpoint())

	status, body := doGet(t, tester, site, "/")
	if status != http.StatusOK {
		t.Fatalf("status: want 200, got %d (body=%q)", status, body)
	}

	indexKey := site + "/deploys/v1/index.html"
	ops := stub.opsFor(indexKey)
	gets := 0
	for _, op := range ops {
		if strings.HasPrefix(op, http.MethodGet+" ") {
			gets++
		}
	}
	if gets != 1 {
		t.Fatalf("body fetches for %s: want 1, got %d (ops=%v, all=%v)", indexKey, gets, ops, stub.allOps())
	}
}

func TestIntegration_ServedObjectTellsTheBrowserToRevalidate(t *testing.T) {
	stub := startS3Stub(t)
	site := "site-a." + rootDomain

	uploadDeployFixtures(t, stub, site, "v1")
	stub.putAlias(site, "production", "v1")

	tester := startCaddy(t, stub.endpoint())

	resp, _ := doGetResponse(t, tester, site, "/index.html")
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status: want 200, got %d", resp.StatusCode)
	}
	if got := resp.Header.Get("Cache-Control"); got != documentCacheControl {
		t.Fatalf("Cache-Control: want %q, got %q", documentCacheControl, got)
	}
}

func TestIntegration_OversizeObjectAnswers400(t *testing.T) {
	stub := startS3Stub(t)
	site := "site-a." + rootDomain

	uploadDeployFixtures(t, stub, site, "v1")
	stub.putAlias(site, "production", "v1")
	stub.put(site+"/deploys/v1/big.html", strings.Repeat("x", 512), "text/html")

	tester := startCaddyWithMaxFileSize(t, stub.endpoint(), 64)

	resp, body := doGetResponse(t, tester, site, "/big.html")
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status: want 400, got %d (body=%q)", resp.StatusCode, body)
	}
	if body != "Bad Request" {
		t.Errorf("handle_errors should answer the oversize case, got %q", body)
	}
	if got := resp.Header.Get("Cache-Control"); got != errorCacheControl {
		t.Errorf("Cache-Control on a 400: want %q, got %q", errorCacheControl, got)
	}
}

func TestIntegration_ErrorResponseIsNeverStored(t *testing.T) {
	stub := startS3Stub(t)
	tester := startCaddy(t, stub.endpoint())

	resp, _ := doGetResponse(t, tester, "dead."+rootDomain, "/")
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("status: want 404, got %d", resp.StatusCode)
	}
	if got := resp.Header.Get("Cache-Control"); got != errorCacheControl {
		t.Fatalf("Cache-Control on a 404: want %q, got %q", errorCacheControl, got)
	}
}

func TestIntegration_BareNotFoundAliasIs404(t *testing.T) {
	stub := startS3Stub(t)
	stub.setFailure(http.StatusNotFound)

	tester := startCaddy(t, stub.endpoint())

	status, body := doGet(t, tester, "dead."+rootDomain, "/")
	if status != http.StatusNotFound {
		t.Fatalf("status: want 404, got %d (body=%q)", status, body)
	}
}

func TestIntegration_UpstreamServerErrorIs503(t *testing.T) {
	stub := startS3Stub(t)
	stub.setFailure(http.StatusInternalServerError)

	tester := startCaddy(t, stub.endpoint())

	status, body := doGet(t, tester, "site-a."+rootDomain, "/")
	if status != http.StatusServiceUnavailable {
		t.Fatalf("status: want 503, got %d (body=%q)", status, body)
	}
}

func TestIntegration_BodyFetchFailureNeverServes200(t *testing.T) {
	stub := startS3Stub(t)
	site := "site-a." + rootDomain

	uploadDeployFixtures(t, stub, site, "v1")
	stub.putAlias(site, "production", "v1")
	stub.failGetForKeyOnly(site+"/deploys/v1/index.html", http.StatusInternalServerError)

	tester := startCaddy(t, stub.endpoint())

	url := fmt.Sprintf("http://localhost:%d/index.html", caddyHTTPPort)
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	req.Host = site

	resp, err := tester.Client.Do(req)
	if err != nil {
		t.Fatalf("GET /index.html: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()
	body, readErr := io.ReadAll(resp.Body)

	if resp.StatusCode != http.StatusInternalServerError {
		t.Fatalf("r2 body fetch failed, caddy answered %d (delivered=%d readErr=%v); status monitoring cannot see the outage",
			resp.StatusCode, len(body), readErr)
	}
	if got := resp.Header.Get("Cache-Control"); got != "" {
		t.Errorf("ServeContent writes this error itself, so handle_errors cannot set a header; got %q", got)
	}
	if strings.Contains(string(body), "Server Error") {
		t.Errorf("handle_errors is unreachable on this path; body was %q", body)
	}
}

func TestIntegration_HeadFailureReachesTheVisitorAs5xx(t *testing.T) {
	stub := startS3Stub(t)
	site := "site-a." + rootDomain

	uploadDeployFixtures(t, stub, site, "v1")
	stub.putAlias(site, "production", "v1")
	stub.failEveryMethodForKeyOnly(site+"/deploys/v1/index.html", http.StatusInternalServerError)

	tester := startCaddy(t, stub.endpoint())

	resp, body := doGetResponse(t, tester, site, "/index.html")
	if resp.StatusCode < 500 {
		t.Fatalf("an R2 metadata failure must reach the visitor as 5xx, got %d (body=%q)", resp.StatusCode, body)
	}
	if resp.StatusCode == http.StatusNotFound {
		t.Fatal("caddy's mapDirOpenError walk must not downgrade an outage to a 404")
	}
}

func TestIntegration_HeadOnASkewedObjectSizesTruthfully(t *testing.T) {
	stub := startS3Stub(t)
	site := "site-a." + rootDomain

	uploadDeployFixtures(t, stub, site, "v1")
	stub.putAlias(site, "production", "v1")
	stub.putSkewed(site+"/deploys/v1/skew.html", "SHORT-BODY", "text/html", 5000)

	tester := startCaddy(t, stub.endpoint())

	req, err := http.NewRequest(http.MethodHead,
		fmt.Sprintf("http://localhost:%d/skew.html", caddyHTTPPort), nil)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	req.Host = site

	resp, err := tester.Client.Do(req)
	if err != nil {
		t.Fatalf("HEAD /skew.html: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status: want 200, got %d", resp.StatusCode)
	}
	if resp.ContentLength != int64(len("SHORT-BODY")) {
		t.Fatalf("Content-Length: want the true %d, got the HeadObject %d",
			len("SHORT-BODY"), resp.ContentLength)
	}
}

func TestIntegration_ValidatorChangesWithTheDeploy(t *testing.T) {
	stub := startS3Stub(t)
	site := "site-a." + rootDomain

	uploadDeployFixtures(t, stub, site, "v1")
	uploadDeployFixtures(t, stub, site, "v2")
	stub.putAlias(site, "production", "v1")

	tester := startCaddy(t, stub.endpoint())

	first, _ := doGetResponse(t, tester, site, "/index.html")
	firstTag := first.Header.Get("Etag")
	if firstTag == "" {
		t.Fatal("a served object must carry a validator")
	}

	stub.putAlias(site, "production", "v2")
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		next, _ := doGetResponse(t, tester, site, "/index.html")
		if tag := next.Header.Get("Etag"); tag != firstTag {
			return
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatalf("the validator never changed after the alias flip: still %s", firstTag)
}

func TestIntegration_ConditionalRequestAfterAFlipRefetches(t *testing.T) {
	stub := startS3Stub(t)
	site := "site-a." + rootDomain

	uploadDeployFixtures(t, stub, site, "v1")
	uploadDeployFixtures(t, stub, site, "v2")
	stub.putAlias(site, "production", "v1")

	tester := startCaddy(t, stub.endpoint())

	first, firstBody := doGetResponse(t, tester, site, "/index.html")
	staleTag := first.Header.Get("Etag")
	assertBodyContains(t, firstBody, "V1")

	stub.putAlias(site, "production", "v2")
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		req, err := http.NewRequest(http.MethodGet,
			fmt.Sprintf("http://localhost:%d/index.html", caddyHTTPPort), nil)
		if err != nil {
			t.Fatalf("new request: %v", err)
		}
		req.Host = site
		req.Header.Set("If-None-Match", staleTag)

		resp, err := tester.Client.Do(req)
		if err != nil {
			t.Fatalf("conditional GET: %v", err)
		}
		body, _ := io.ReadAll(resp.Body)
		_ = resp.Body.Close()

		if resp.StatusCode == http.StatusNotModified {
			time.Sleep(100 * time.Millisecond)
			continue
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("status: want 200, got %d", resp.StatusCode)
		}
		assertBodyContains(t, string(body), "V2")
		return
	}
	t.Fatal("a stale validator kept answering 304 after the alias flip")
}

func TestIntegration_UnsupportedMethodAnswers405(t *testing.T) {
	stub := startS3Stub(t)
	site := "site-a." + rootDomain

	uploadDeployFixtures(t, stub, site, "v1")
	stub.putAlias(site, "production", "v1")

	tester := startCaddy(t, stub.endpoint())

	req, err := http.NewRequest(http.MethodDelete,
		fmt.Sprintf("http://localhost:%d/index.html", caddyHTTPPort), nil)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	req.Host = site

	resp, err := tester.Client.Do(req)
	if err != nil {
		t.Fatalf("DELETE /index.html: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusMethodNotAllowed {
		t.Fatalf("status: want 405, got %d", resp.StatusCode)
	}
	if got := resp.Header.Get("Etag"); got != "" {
		t.Errorf("an error response must not carry a validator, got %q", got)
	}
}

func TestIntegration_MissingSite404(t *testing.T) {
	stub := startS3Stub(t)
	tester := startCaddy(t, stub.endpoint())

	status, _ := doGet(t, tester, "dead."+rootDomain, "/")
	if status != http.StatusNotFound {
		t.Fatalf("status: want 404, got %d", status)
	}
}

func TestIntegration_HeadGetSizeSkewServesTheTrueLength(t *testing.T) {
	stub := startS3Stub(t)
	site := "site-a." + rootDomain

	uploadDeployFixtures(t, stub, site, "v1")
	stub.putAlias(site, "production", "v1")
	stub.putSkewed(site+"/deploys/v1/skew.html", "SHORT-BODY", "text/html", 5000)

	tester := startCaddy(t, stub.endpoint())

	resp, body := doGetResponse(t, tester, site, "/skew.html")
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status: want 200, got %d", resp.StatusCode)
	}
	if body != "SHORT-BODY" {
		t.Fatalf("body: want %q, got %q", "SHORT-BODY", body)
	}
	if resp.ContentLength != int64(len(body)) {
		t.Fatalf("declared %d, delivered %d", resp.ContentLength, len(body))
	}
}

func TestIntegration_HeadCostsOneBodyFetchAndSizesTruthfully(t *testing.T) {
	stub := startS3Stub(t)
	site := "site-a." + rootDomain

	uploadDeployFixtures(t, stub, site, "v1")
	stub.putAlias(site, "production", "v1")

	tester := startCaddy(t, stub.endpoint())
	_, want := doGet(t, tester, site, "/index.html")

	before := len(stub.allOps())
	req, err := http.NewRequest(http.MethodHead,
		fmt.Sprintf("http://localhost:%d/index.html", caddyHTTPPort), nil)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	req.Host = site

	resp, err := tester.Client.Do(req)
	if err != nil {
		t.Fatalf("HEAD /index.html: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status: want 200, got %d", resp.StatusCode)
	}
	if resp.ContentLength != int64(len(want)) {
		t.Errorf("Content-Length: want the delivered %d, got %d", len(want), resp.ContentLength)
	}

	gets := 0
	for _, op := range stub.allOps()[before:] {
		if strings.HasPrefix(op, http.MethodGet+" ") {
			gets++
		}
	}
	if gets != 1 {
		t.Fatalf("body fetches for one HEAD: want 1, got %d (ops=%v)", gets, stub.allOps()[before:])
	}
}
