package r2alias_test

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

type stubObject struct {
	body        []byte
	contentType string
	modTime     time.Time
}

type s3Stub struct {
	server *httptest.Server
	bucket string

	mu         sync.RWMutex
	objects    map[string]stubObject
	failStatus int
	requests   []string
}

func startS3Stub(t *testing.T) *s3Stub {
	t.Helper()
	s := &s3Stub{bucket: testBucket, objects: make(map[string]stubObject)}
	s.server = httptest.NewServer(http.HandlerFunc(s.serve))
	t.Cleanup(s.server.Close)
	return s
}

func (s *s3Stub) endpoint() string { return s.server.URL }

func (s *s3Stub) put(key, body, contentType string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.objects[key] = stubObject{
		body:        []byte(body),
		contentType: contentType,
		modTime:     time.Now().UTC().Truncate(time.Second),
	}
}

// setFailure makes every response a bodyless status, so the SDK yields a
// generic error rather than a typed NoSuchKey.
func (s *s3Stub) setFailure(status int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.failStatus = status
}

func (s *s3Stub) putAlias(site, aliasName, deployID string) {
	s.put(site+"/"+aliasName, deployID, "text/plain")
}

// allOps returns every recorded "<METHOD> <key>", in order.
func (s *s3Stub) allOps() []string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return append([]string(nil), s.requests...)
}

// opsFor returns every recorded "<METHOD> <key>" for one key.
func (s *s3Stub) opsFor(key string) []string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	var out []string
	for _, op := range s.requests {
		if strings.HasSuffix(op, " "+key) {
			out = append(out, op)
		}
	}
	return out
}

func (s *s3Stub) serve(w http.ResponseWriter, req *http.Request) {
	key, ok := strings.CutPrefix(req.URL.Path, "/"+s.bucket+"/")

	s.mu.Lock()
	s.requests = append(s.requests, req.Method+" "+key)
	fail := s.failStatus
	obj, found := s.objects[key]
	s.mu.Unlock()

	if fail != 0 {
		w.WriteHeader(fail)
		return
	}
	if !ok {
		writeS3Error(w, req, http.StatusNotFound, "NoSuchBucket", req.URL.Path)
		return
	}
	if !found {
		writeS3Error(w, req, http.StatusNotFound, "NoSuchKey", key)
		return
	}

	if obj.contentType != "" {
		w.Header().Set("Content-Type", obj.contentType)
	}
	w.Header().Set("Content-Length", strconv.Itoa(len(obj.body)))
	w.Header().Set("Last-Modified", obj.modTime.Format(http.TimeFormat))
	w.WriteHeader(http.StatusOK)
	if req.Method != http.MethodHead {
		_, _ = w.Write(obj.body)
	}
}

// The AWS SDK needs this XML shape to deserialize a typed *s3types.NoSuchKey;
// a bare 404 only satisfies the generic ResponseError path, which fetchAlias
// does not check.
func writeS3Error(w http.ResponseWriter, req *http.Request, status int, code, key string) {
	w.Header().Set("Content-Type", "application/xml")
	w.WriteHeader(status)
	if req.Method == http.MethodHead {
		return
	}
	fmt.Fprintf(w, `<?xml version="1.0" encoding="UTF-8"?>`+
		`<Error><Code>%s</Code><Message>The specified key does not exist.</Message>`+
		`<Key>%s</Key></Error>`, code, key)
}
