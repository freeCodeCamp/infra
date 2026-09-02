package r2alias_test

import (
	"os"
	"path/filepath"
	"regexp"
	"strconv"
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

func indentOf(line string) int {
	return len(line) - len(strings.TrimLeft(line, " "))
}

func limitsMemoryMiB(t *testing.T, path, raw string) int {
	t.Helper()

	lines := strings.Split(raw, "\n")
	for i, line := range lines {
		if strings.TrimSpace(line) != "limits:" {
			continue
		}
		for _, next := range lines[i+1:] {
			if strings.TrimSpace(next) == "" {
				continue
			}
			if indentOf(next) <= indentOf(line) {
				break
			}
			value, ok := strings.CutPrefix(strings.TrimSpace(next), "memory:")
			if !ok {
				continue
			}
			mib, err := strconv.Atoi(strings.TrimSuffix(strings.TrimSpace(value), "Mi"))
			if err != nil {
				t.Fatalf("parse resources.limits.memory in %s: %v", path, err)
			}
			return mib
		}
	}
	t.Fatalf("%s declares no resources.limits.memory", path)
	return 0
}

func TestChartMemoryLimitsLeaveHeadroomForTheBudget(t *testing.T) {
	t.Parallel()

	inFlightMiB, err := strconv.Atoi(chartMaxInFlightBytes)
	if err != nil {
		t.Fatalf("parse %s: %v", chartMaxInFlightBytes, err)
	}
	inFlightMiB /= 1024 * 1024

	deployment, err := os.ReadFile(filepath.Join("..", "k3s", "gxy-cassiopeia", "apps", "caddy",
		"charts", "caddy", "templates", "deployment.yaml"))
	if err != nil {
		t.Fatalf("read deployment.yaml: %v", err)
	}
	if !regexp.MustCompile(`name:\s*GOMEMLIMIT\n\s+value:\s*\{\{\s*\.Values\.goMemLimit`).Match(deployment) {
		t.Error("the Deployment must wire .Values.goMemLimit into GOMEMLIMIT, or the soft limit never reaches the pod")
	}

	for _, values := range []string{
		filepath.Join("..", "k3s", "gxy-cassiopeia", "apps", "caddy", "charts", "caddy", "values.yaml"),
		filepath.Join("..", "k3s", "gxy-cassiopeia", "apps", "caddy", "values.production.yaml"),
	} {
		raw, readErr := os.ReadFile(values)
		if readErr != nil {
			t.Fatalf("read %s: %v", values, readErr)
		}

		podMiB := limitsMemoryMiB(t, values, string(raw))

		soft := regexp.MustCompile(`(?m)^goMemLimit:\s*(\d+)MiB\s*$`).FindStringSubmatch(string(raw))
		if soft == nil {
			t.Fatalf("%s sets no goMemLimit, so the soft limit never engages", values)
		}
		softMiB, convErr := strconv.Atoi(soft[1])
		if convErr != nil {
			t.Fatalf("parse goMemLimit in %s: %v", values, convErr)
		}

		if softMiB >= podMiB {
			t.Errorf("%s: goMemLimit %dMiB must sit below the pod limit %dMi or it never engages",
				values, softMiB, podMiB)
		}
		if softMiB <= inFlightMiB {
			t.Errorf("%s: goMemLimit %dMiB must exceed the %dMiB in-flight budget",
				values, softMiB, inFlightMiB)
		}
	}
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

	if !strings.Contains(body, ":"+chartMetricsPort+" {") {
		t.Errorf("the chart must expose the metrics listener on :%s", chartMetricsPort)
	}
	values, err := os.ReadFile(filepath.Join("..", "k3s", "gxy-cassiopeia", "apps", "caddy",
		"charts", "caddy", "values.yaml"))
	if err != nil {
		t.Fatalf("read values.yaml: %v", err)
	}
	if !strings.Contains(string(values), "port: "+chartMetricsPort) {
		t.Errorf("values.yaml must publish the same metrics port %s as the Caddyfile", chartMetricsPort)
	}

	filesystem := blockAfter(t, body, "filesystem r2 r2 {")
	if !strings.Contains(filesystem, "max_file_size        "+chartMaxFileSize) {
		t.Errorf("the chart must cap max_file_size at %s bytes; one in-flight fetch buffers that much per request",
			chartMaxFileSize)
	}
	if !strings.Contains(filesystem, "max_in_flight_bytes  "+chartMaxInFlightBytes) {
		t.Errorf("the chart must cap max_in_flight_bytes at %s bytes so the budget fits the pod limit",
			chartMaxInFlightBytes)
	}
	if strings.Contains(body, "servers {") {
		t.Error("the nested servers/metrics option is deprecated on caddy 2.11.3; use the global metrics option")
	}

	errors := blockAfter(t, body, "handle_errors {")
	if !strings.Contains(errors, `header Cache-Control "`+errorCacheControl+`"`) {
		t.Errorf("handle_errors must send %q, the policy the integration tests prove", errorCacheControl)
	}
	if strings.Contains(errors, documentCacheControl) {
		t.Errorf("handle_errors must not send the serving policy %q", documentCacheControl)
	}
}
