package r2alias_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/caddyserver/caddy/v2/caddyconfig"
	_ "github.com/caddyserver/caddy/v2/caddyconfig/httpcaddyfile"
)

var chartConfigMap = filepath.Join("..", "k3s", "gxy-cassiopeia", "apps", "caddy",
	"charts", "caddy", "templates", "configmap.yaml")

func chartCaddyfile(t *testing.T) string {
	t.Helper()

	raw, err := os.ReadFile(chartConfigMap)
	if err != nil {
		t.Fatalf("read %s: %v", chartConfigMap, err)
	}

	lines := strings.Split(string(raw), "\n")
	start := -1
	for i, line := range lines {
		if strings.TrimSpace(line) == "Caddyfile: |" {
			start = i + 1
			break
		}
	}
	if start < 0 {
		t.Fatalf("%s carries no `Caddyfile: |` block", chartConfigMap)
	}

	const indent = "    "
	var block []string
	for _, line := range lines[start:] {
		if strings.TrimSpace(line) == "" {
			block = append(block, "")
			continue
		}
		if !strings.HasPrefix(line, indent) {
			break
		}
		block = append(block, strings.TrimPrefix(line, indent))
	}
	return strings.Join(block, "\n")
}

func TestChartCaddyfileAdaptsUnderThisModuleSet(t *testing.T) {
	for name, value := range map[string]string{
		"R2_BUCKET":             "gxy-cassiopeia",
		"R2_ENDPOINT":           "https://r2.example",
		"AWS_ACCESS_KEY_ID":     "kid",
		"AWS_SECRET_ACCESS_KEY": "sak",
	} {
		t.Setenv(name, value)
	}

	body := chartCaddyfile(t)
	if !strings.Contains(body, "r2_alias") {
		t.Fatalf("extracted block is not the site config: %q", body)
	}

	adapter := caddyconfig.GetAdapter("caddyfile")
	if adapter == nil {
		t.Fatal("no caddyfile adapter is registered")
	}

	_, warnings, err := adapter.Adapt([]byte(body), map[string]any{"filename": "Caddyfile"})
	if err != nil {
		t.Fatalf("the chart Caddyfile does not adapt, so this image would refuse to start: %v", err)
	}
	for _, w := range warnings {
		if strings.Contains(w.Message, "not formatted") {
			continue
		}
		t.Errorf("adapt warning at %s:%d: %s", w.File, w.Line, w.Message)
	}
}

func blockAfter(t *testing.T, body, opener string) string {
	t.Helper()

	start := strings.Index(body, opener)
	if start < 0 {
		t.Fatalf("the chart Caddyfile has no %q block", opener)
	}
	rest := body[start+len(opener):]
	depth := 1
	for i, r := range rest {
		switch r {
		case '{':
			depth++
		case '}':
			depth--
			if depth == 0 {
				return rest[:i]
			}
		}
	}
	t.Fatalf("the %q block never closes", opener)
	return ""
}

func TestChartCaddyfileCarriesTheTestedCachePolicy(t *testing.T) {
	t.Parallel()

	body := chartCaddyfile(t)

	serving := blockAfter(t, body, "handle {")
	if !strings.Contains(serving, `header Cache-Control "`+documentCacheControl+`"`) {
		t.Errorf("the serving block must send %q, the policy the integration tests prove", documentCacheControl)
	}
	if strings.Contains(serving, errorCacheControl) {
		t.Errorf("the serving block must not send %q", errorCacheControl)
	}

	errors := blockAfter(t, body, "handle_errors {")
	if !strings.Contains(errors, `header Cache-Control "`+errorCacheControl+`"`) {
		t.Errorf("handle_errors must send %q, the policy the integration tests prove", errorCacheControl)
	}
	if strings.Contains(errors, documentCacheControl) {
		t.Errorf("handle_errors must not send the serving policy %q", documentCacheControl)
	}
}
