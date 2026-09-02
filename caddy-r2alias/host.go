package r2alias

import (
	"fmt"
	"net"
	"strings"
)

// https://github.com/caddyserver/caddy/blob/v2.11.3/modules/caddyhttp/matchers.go#L308-L316
func normaliseHost(host string) string {
	if bare, _, err := net.SplitHostPort(host); err == nil {
		host = bare
	}
	host = strings.TrimPrefix(host, "[")
	host = strings.TrimSuffix(host, "]")
	return strings.ToLower(strings.TrimSuffix(host, "."))
}

// parseSiteAndAlias extracts (site, alias) from a Host header.
//
// Preview routing keys off the rightmost label of the site prefix being
// equal to the configured preview subdomain (D35, supersedes D5
// double-dash suffix scheme). Hostname `<labels>.preview.<root>` resolves
// to site `<labels>.<root>` with alias=preview. Anywhere else, a `preview`
// token is part of the site name and routing falls through to production
// — preview and production share the same `{site}/deploys/{id}/*` prefix
// in R2; only the alias file differs.
func parseSiteAndAlias(host, rootDomain, previewSubdomain string) (site, alias string, err error) {
	// site is spliced into the storage path; a separator would add segments.
	if strings.ContainsAny(host, `/\`) {
		return "", "", fmt.Errorf("host %q contains a path separator", host)
	}

	host = normaliseHost(host)
	rootDomain = strings.ToLower(rootDomain)
	previewSubdomain = strings.ToLower(previewSubdomain)

	suffix := "." + rootDomain
	if !strings.HasSuffix(host, suffix) {
		return "", "", fmt.Errorf("host %q is not under root domain %q", host, rootDomain)
	}
	prefix := strings.TrimSuffix(host, suffix)
	if prefix == "" {
		return "", "", fmt.Errorf("host %q has no subdomain", host)
	}

	if i := strings.LastIndexByte(prefix, '.'); i >= 0 {
		if prefix[i+1:] == previewSubdomain {
			sitePrefix := prefix[:i]
			if sitePrefix == "" {
				return "", "", fmt.Errorf("host %q has empty site label before preview subdomain", host)
			}
			return sitePrefix + suffix, "preview", nil
		}
	} else if prefix == previewSubdomain {
		return "", "", fmt.Errorf("host %q has no site label (preview-only apex)", host)
	}

	return prefix + suffix, "production", nil
}
