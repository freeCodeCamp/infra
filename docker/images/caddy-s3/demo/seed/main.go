// Command seed primes the demo S3Mock bucket with two deploys and a single
// atomic alias file, then exits. Re-run with -alias v2 (or v1) to demonstrate
// the production alias flip without restarting anything else.
package main

import (
	"bytes"
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	s3types "github.com/aws/aws-sdk-go-v2/service/s3/types"
)

const (
	bucket = "demo"
	site   = "demo.test.camp"
)

func main() {
	endpoint := flag.String("endpoint", "http://s3mock:9090", "S3-compatible endpoint")
	alias := flag.String("alias", "v1", "alias target: v1 or v2")
	flag.Parse()

	if *alias != "v1" && *alias != "v2" {
		log.Fatalf("-alias must be v1 or v2, got %q", *alias)
	}

	ctx := context.Background()
	cfg, err := config.LoadDefaultConfig(ctx,
		config.WithRegion("us-east-1"),
		config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider("demo", "demo", "")),
	)
	if err != nil {
		log.Fatalf("load aws config: %v", err)
	}
	client := s3.NewFromConfig(cfg, func(o *s3.Options) {
		o.BaseEndpoint = aws.String(*endpoint)
		o.UsePathStyle = true
	})

	if err := waitForBucket(ctx, client); err != nil {
		log.Fatalf("bucket not ready: %v", err)
	}

	// Upload both deploys so the flip lands on something real.
	for _, v := range []string{"v1", "v2"} {
		body, err := os.ReadFile("/fixtures/" + v + "/index.html")
		if err != nil {
			log.Fatalf("read fixture %s: %v", v, err)
		}
		if err := put(ctx, client, site+"/deploys/"+v+"/index.html", body, "text/html"); err != nil {
			log.Fatalf("put deploy %s: %v", v, err)
		}
		fmt.Printf("  uploaded %s/deploys/%s/index.html (%d bytes)\n", site, v, len(body))
	}

	// Atomically point production at the requested version — same mechanic
	// the Woodpecker pipeline uses in prod (single PutObject on the alias
	// file).
	if err := put(ctx, client, site+"/production", []byte(*alias), "text/plain"); err != nil {
		log.Fatalf("put alias: %v", err)
	}
	fmt.Printf("  alias %s/production -> %s\n", site, *alias)
	fmt.Println("seed complete.")
}

func put(ctx context.Context, client *s3.Client, key string, body []byte, contentType string) error {
	_, err := client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(bucket),
		Key:         aws.String(key),
		Body:        bytes.NewReader(body),
		ContentType: aws.String(contentType),
	})
	return err
}

// waitForBucket polls HeadBucket until S3Mock is accepting requests. compose's
// service_healthy gate sometimes fires before Tomcat finishes warming up.
func waitForBucket(ctx context.Context, client *s3.Client) error {
	deadline := time.Now().Add(30 * time.Second)
	var lastErr error
	for time.Now().Before(deadline) {
		_, err := client.HeadBucket(ctx, &s3.HeadBucketInput{Bucket: aws.String(bucket)})
		if err == nil {
			return nil
		}
		var notFound *s3types.NotFound
		if errors.As(err, &notFound) {
			return fmt.Errorf("bucket %q does not exist (check COM_ADOBE_TESTING_S3MOCK_STORE_INITIAL_BUCKETS on s3mock service)", bucket)
		}
		lastErr = err
		time.Sleep(500 * time.Millisecond)
	}
	return fmt.Errorf("timed out waiting for bucket: %w", lastErr)
}
