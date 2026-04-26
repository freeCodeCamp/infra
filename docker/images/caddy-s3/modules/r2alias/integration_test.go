//go:build integration

package r2alias_test

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/caddyserver/caddy/v2/caddytest"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"

	_ "github.com/freeCodeCamp-Universe/infra/docker/images/caddy-s3/modules/r2alias"
)

// Pin Adobe S3Mock by major version tag (D30 — no :latest).
const s3MockImage = "adobe/s3mock:5.0.0"

// testBucket matches the initial bucket provisioned by S3Mock on startup.
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

type s3Mock struct {
	endpoint string
	client   *s3.Client
	bucket   string
}

func startS3Mock(t *testing.T) *s3Mock {
	t.Helper()
	testcontainers.SkipIfProviderIsNotHealthy(t)
	ctx := context.Background()

	req := testcontainers.GenericContainerRequest{
		ContainerRequest: testcontainers.ContainerRequest{
			Image:        s3MockImage,
			ExposedPorts: []string{"9090/tcp"},
			Env: map[string]string{
				"COM_ADOBE_TESTING_S3MOCK_STORE_INITIAL_BUCKETS": testBucket,
			},
			WaitingFor: wait.ForListeningPort("9090/tcp").WithStartupTimeout(60 * time.Second),
		},
		Started: true,
	}

	container, err := testcontainers.GenericContainer(ctx, req)
	if err != nil {
		t.Fatalf("start s3mock container: %v", err)
	}
	t.Cleanup(func() {
		if err := container.Terminate(context.Background()); err != nil {
			t.Logf("terminate s3mock container: %v", err)
		}
	})

	host, err := container.Host(ctx)
	if err != nil {
		t.Fatalf("container host: %v", err)
	}
	port, err := container.MappedPort(ctx, "9090/tcp")
	if err != nil {
		t.Fatalf("mapped port: %v", err)
	}
	endpoint := fmt.Sprintf("http://%s:%s", host, port.Port())

	awsCfg, err := config.LoadDefaultConfig(ctx,
		config.WithRegion("us-east-1"),
		config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider("test", "test", "")),
	)
	if err != nil {
		t.Fatalf("aws config: %v", err)
	}
	client := s3.NewFromConfig(awsCfg, func(o *s3.Options) {
		o.BaseEndpoint = aws.String(endpoint)
		o.UsePathStyle = true
	})

	return &s3Mock{endpoint: endpoint, client: client, bucket: testBucket}
}

// uploadDeployFixtures uploads testdata/site-a/deploys/<version>/* to the
// bucket under <site>/deploys/<version>/*. The disk layout is independent of
// the S3 prefix so one fixture set can back multiple site names.
func uploadDeployFixtures(t *testing.T, client *s3.Client, bucket, site, version string) {
	t.Helper()
	ctx := context.Background()

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

		key := fmt.Sprintf("%s/deploys/%s/%s", site, version, rel)
		_, putErr := client.PutObject(ctx, &s3.PutObjectInput{
			Bucket:      aws.String(bucket),
			Key:         aws.String(key),
			Body:        bytes.NewReader(body),
			ContentType: aws.String("text/html"),
		})
		return putErr
	})
	if err != nil {
		t.Fatalf("upload fixtures %s/%s: %v", site, version, err)
	}
}

func putAlias(t *testing.T, client *s3.Client, bucket, site, aliasName, deployID string) {
	t.Helper()
	_, err := client.PutObject(context.Background(), &s3.PutObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(fmt.Sprintf("%s/%s", site, aliasName)),
		Body:   strings.NewReader(deployID),
	})
	if err != nil {
		t.Fatalf("put alias %s/%s=%s: %v", site, aliasName, deployID, err)
	}
}

func startCaddy(t *testing.T, s3mockEndpoint string) *caddytest.Tester {
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
		testBucket, s3mockEndpoint,
		caddyHTTPPort,
		testBucket, s3mockEndpoint,
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
	mock := startS3Mock(t)
	site := "site-a." + rootDomain

	uploadDeployFixtures(t, mock.client, mock.bucket, site, "v1")
	putAlias(t, mock.client, mock.bucket, site, "production", "v1")

	tester := startCaddy(t, mock.endpoint)

	status, body := doGet(t, tester, site, "/")
	if status != http.StatusOK {
		t.Fatalf("status: want 200, got %d (body=%q)", status, body)
	}
	assertBodyContains(t, body, "V1")
}

func TestIntegration_AliasFlip(t *testing.T) {
	mock := startS3Mock(t)
	site := "site-a." + rootDomain

	uploadDeployFixtures(t, mock.client, mock.bucket, site, "v1")
	uploadDeployFixtures(t, mock.client, mock.bucket, site, "v2")
	putAlias(t, mock.client, mock.bucket, site, "production", "v1")

	tester := startCaddy(t, mock.endpoint)

	status, body := doGet(t, tester, site, "/")
	if status != http.StatusOK {
		t.Fatalf("pre-flip status: want 200, got %d (body=%q)", status, body)
	}
	assertBodyContains(t, body, "V1")

	putAlias(t, mock.client, mock.bucket, site, "production", "v2")

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
	mock := startS3Mock(t)
	prodSite := "site-a." + rootDomain
	previewHost := "site-a.preview." + rootDomain

	uploadDeployFixtures(t, mock.client, mock.bucket, prodSite, "v2")
	putAlias(t, mock.client, mock.bucket, prodSite, "preview", "v2")

	tester := startCaddy(t, mock.endpoint)

	status, body := doGet(t, tester, previewHost, "/")
	if status != http.StatusOK {
		t.Fatalf("status: want 200, got %d (body=%q)", status, body)
	}
	assertBodyContains(t, body, "V2")
}

func TestIntegration_MissingSite404(t *testing.T) {
	mock := startS3Mock(t)
	tester := startCaddy(t, mock.endpoint)

	status, _ := doGet(t, tester, "dead."+rootDomain, "/")
	if status != http.StatusNotFound {
		t.Fatalf("status: want 404, got %d", status)
	}
}
