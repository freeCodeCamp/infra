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
	}
}

:%d {
	r2_alias {
		bucket %s
		endpoint %s
		region us-east-1
		access_key_id test
		secret_access_key test
		cache_ttl %s
		root_domain %s
	}
	file_server {
		fs r2
	}
}
`,
		caddyAdminPort, caddyHTTPPort, caddyHTTPSPort,
		testBucket, s3Endpoint,
		caddyHTTPPort,
		testBucket, s3Endpoint,
		cacheTTL, rootDomain,
	)
	tester := caddytest.NewTester(t)
	tester.InitServer(caddyfile, "caddyfile")
	return tester
}

// doGet issues an HTTP GET with a virtual Host header and returns status + body.
// The TCP target is always the caddytest HTTP listener on localhost.
func doGet(t *testing.T, tester *caddytest.Tester, host, path string) (int, string) {
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
	return resp.StatusCode, string(body)
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

func TestIntegration_MissingSite404(t *testing.T) {
	stub := startS3Stub(t)
	tester := startCaddy(t, stub.endpoint())

	status, _ := doGet(t, tester, "dead."+rootDomain, "/")
	if status != http.StatusNotFound {
		t.Fatalf("status: want 404, got %d", status)
	}
}
