package r2alias

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"go.uber.org/zap"
)

const testMaxFileSize int64 = 1024

func newWiredR2FS(t *testing.T, handler http.HandlerFunc) *R2FS {
	t.Helper()

	srv := httptest.NewServer(handler)
	t.Cleanup(srv.Close)

	r := &R2FS{
		Bucket:      "test-bucket",
		Endpoint:    srv.URL,
		Region:      "auto",
		MaxFileSize: testMaxFileSize,
		logger:      zap.NewNop(),
	}
	r.client = s3.NewFromConfig(aws.Config{
		Region: "auto",
		Credentials: credentials.NewStaticCredentialsProvider(
			"test", "test", ""),
	}, func(o *s3.Options) {
		o.BaseEndpoint = aws.String(srv.URL)
		o.UsePathStyle = true
	})
	return r
}

func writeNoSuchKey(w http.ResponseWriter, req *http.Request) {
	w.Header().Set("Content-Type", "application/xml")
	w.WriteHeader(http.StatusNotFound)
	if req.Method == http.MethodHead {
		return
	}
	fmt.Fprint(w, `<?xml version="1.0" encoding="UTF-8"?>`+
		`<Error><Code>NoSuchKey</Code><Message>no such key</Message></Error>`)
}

func TestGetObject_ServesTheBody(t *testing.T) {
	t.Parallel()
	r := newWiredR2FS(t, func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		w.Header().Set("Content-Length", "4")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("okay"))
	})

	obj, err := r.getObject(context.Background(), "site/index.html")
	if err != nil {
		t.Fatalf("getObject: %v", err)
	}
	if string(obj.Body) != "okay" {
		t.Errorf("body: want %q, got %q", "okay", obj.Body)
	}
	if obj.Size != 4 {
		t.Errorf("size: want 4, got %d", obj.Size)
	}
	if obj.ContentType != "text/html" {
		t.Errorf("content type: want text/html, got %q", obj.ContentType)
	}
}

func TestGetObject_RejectsADeclaredOversizeObject(t *testing.T) {
	t.Parallel()
	const withinLimit = "small"
	r := newWiredR2FS(t, func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Length", strconv.FormatInt(testMaxFileSize+1, 10))
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(withinLimit))
		w.(http.Flusher).Flush()
		panic(http.ErrAbortHandler)
	})

	_, err := r.getObject(context.Background(), "site/big.bin")
	if !errors.Is(err, errObjectTooLarge) {
		t.Fatalf("the declared length alone must reject before any read, got %v", err)
	}
}

func TestGetObject_RejectsAnUndeclaredOversizeStream(t *testing.T) {
	t.Parallel()
	oversize := strings.Repeat("x", int(testMaxFileSize)*4)
	r := newWiredR2FS(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(oversize))
	})

	_, err := r.getObject(context.Background(), "site/chunked.bin")
	if !errors.Is(err, errObjectTooLarge) {
		t.Fatalf("an object with no declared length must not truncate silently, got %v", err)
	}
}

func TestGetObject_AbortedStreamFailsTheFetch(t *testing.T) {
	t.Parallel()
	r := newWiredR2FS(t, func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Length", "64")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("half"))
		w.(http.Flusher).Flush()
		panic(http.ErrAbortHandler)
	})

	_, err := r.getObject(context.Background(), "site/truncated.html")
	if err == nil {
		t.Fatal("a stream that dies mid-body must fail the fetch")
	}
	if !strings.Contains(err.Error(), "read body") {
		t.Errorf("error should name the read failure, got %v", err)
	}
}

func TestGetObject_MissingKeyIsErrNotExist(t *testing.T) {
	t.Parallel()
	r := newWiredR2FS(t, writeNoSuchKey)

	_, err := r.getObject(context.Background(), "site/missing.html")
	if !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("want fs.ErrNotExist, got %v", err)
	}
}

func TestGetObject_ServerErrorIsAnUpstreamFailure(t *testing.T) {
	t.Parallel()
	r := newWiredR2FS(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	})

	_, err := r.getObject(context.Background(), "site/index.html")
	if err == nil {
		t.Fatal("a 500 must fail the fetch")
	}
	if errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("a 500 must not read as missing, got %v", err)
	}
	if !strings.Contains(err.Error(), "upstream 5xx") {
		t.Errorf("error should name the upstream failure, got %v", err)
	}
}

func TestGetObject_ClientErrorIsNotMissing(t *testing.T) {
	t.Parallel()
	r := newWiredR2FS(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusForbidden)
	})

	_, err := r.getObject(context.Background(), "site/index.html")
	if err == nil {
		t.Fatal("a 403 must fail the fetch")
	}
	if errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("a 403 must not read as missing, got %v", err)
	}
}

func TestHeadObject_MissingKeyIsErrNotExist(t *testing.T) {
	t.Parallel()
	r := newWiredR2FS(t, writeNoSuchKey)

	_, err := r.headObject(context.Background(), "site/missing.html")
	if !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("want fs.ErrNotExist, got %v", err)
	}
}

func TestHeadObject_ServerErrorIsAnUpstreamFailure(t *testing.T) {
	t.Parallel()
	r := newWiredR2FS(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	})

	_, err := r.headObject(context.Background(), "site/index.html")
	if err == nil || !strings.Contains(err.Error(), "upstream 5xx") {
		t.Fatalf("error should name the upstream failure, got %v", err)
	}
}

func TestHeadObject_ClientErrorIsNotMissing(t *testing.T) {
	t.Parallel()
	r := newWiredR2FS(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusForbidden)
	})

	_, err := r.headObject(context.Background(), "site/index.html")
	if err == nil {
		t.Fatal("a 403 must fail the head")
	}
	if errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("a 403 must not read as missing, got %v", err)
	}
}

func TestHasIndex_PropagatesAnUpstreamFailure(t *testing.T) {
	t.Parallel()
	r := newWiredR2FS(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	})

	if _, err := r.hasIndex(context.Background(), "site/deploys/v1"); err == nil {
		t.Fatal("an upstream failure during the index probe must not read as absent")
	}
}

func TestHasIndex_ReportsAPresentIndex(t *testing.T) {
	t.Parallel()
	r := newWiredR2FS(t, func(w http.ResponseWriter, req *http.Request) {
		if !strings.HasSuffix(req.URL.Path, "/"+indexFile) {
			writeNoSuchKey(w, req)
			return
		}
		w.Header().Set("Content-Length", "10")
		w.WriteHeader(http.StatusOK)
	})

	has, err := r.hasIndex(context.Background(), "site/deploys/v1")
	if err != nil {
		t.Fatalf("hasIndex: %v", err)
	}
	if !has {
		t.Error("hasIndex should report the index present")
	}
}
