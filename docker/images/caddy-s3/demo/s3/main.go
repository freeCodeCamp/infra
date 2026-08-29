// Command s3 serves a directory tree as a read-only S3-compatible bucket.
// It answers the three operations the Caddy modules issue — GET, HEAD, and a
// NoSuchKey 404 — and nothing else. A key is a file; there are no directories.
package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
)

func main() {
	root := flag.String("root", "/fixtures", "directory served as the bucket")
	bucket := flag.String("bucket", "demo", "bucket name")
	addr := flag.String("addr", ":9090", "listen address")
	flag.Parse()

	srv := &server{root: *root, prefix: "/" + *bucket + "/"}
	log.Printf("serving %s as bucket %q on %s", *root, *bucket, *addr)
	if err := http.ListenAndServe(*addr, srv); err != nil {
		log.Fatalf("listen: %v", err)
	}
}

type server struct {
	root   string
	prefix string
}

func (s *server) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	key, ok := strings.CutPrefix(req.URL.Path, s.prefix)
	if !ok {
		s.deny(w, req, "NoSuchBucket", req.URL.Path)
		return
	}

	rel := filepath.FromSlash(path.Clean("/" + key)[1:])
	if rel == "" || !filepath.IsLocal(rel) {
		s.deny(w, req, "NoSuchKey", key)
		return
	}

	name := filepath.Join(s.root, rel)
	info, err := os.Stat(name)
	if err != nil || info.IsDir() {
		s.deny(w, req, "NoSuchKey", key)
		return
	}

	file, err := os.Open(name)
	if err != nil {
		s.deny(w, req, "NoSuchKey", key)
		return
	}
	defer func() { _ = file.Close() }()

	log.Printf("%s %s -> 200 (%d bytes)", req.Method, key, info.Size())
	http.ServeContent(w, req, info.Name(), info.ModTime(), file)
}

// The AWS SDK needs this XML shape to raise a typed NoSuchKey. A bodyless 404
// only reaches its generic error path.
func (s *server) deny(w http.ResponseWriter, req *http.Request, code, key string) {
	log.Printf("%s %s -> 404 %s", req.Method, key, code)
	w.Header().Set("Content-Type", "application/xml")
	w.WriteHeader(http.StatusNotFound)
	if req.Method == http.MethodHead {
		return
	}
	fmt.Fprintf(w, `<?xml version="1.0" encoding="UTF-8"?>`+
		`<Error><Code>%s</Code><Message>The specified key does not exist.</Message>`+
		`<Key>%s</Key></Error>`, code, key)
}
