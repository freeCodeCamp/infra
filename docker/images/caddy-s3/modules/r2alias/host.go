package r2alias

import (
	"fmt"
	"strings"
)

// parseSiteAndAlias extracts the (site, alias) tuple from a request Host.
//
// Production: "hello-world.freecode.camp" → ("hello-world.freecode.camp", "production").
// Preview:    "hello-world--preview.freecode.camp" → ("hello-world.freecode.camp", "preview").
//
// The preview suffix is recognized ONLY on the leftmost label. An inner-label
// match is part of the site name. The returned site is always the production
// subdomain because production and preview share the same {site}/deploys/{id}/*
// prefix in R2 — they differ only in which alias file they read (RFC §4.3.7).
func parseSiteAndAlias(host, rootDomain, previewSuffix string) (site, alias string, err error) {
	suffix := "." + rootDomain
	if !strings.HasSuffix(host, suffix) {
		return "", "", fmt.Errorf("host %q is not under root domain %q", host, rootDomain)
	}
	prefix := strings.TrimSuffix(host, suffix)
	if prefix == "" {
		return "", "", fmt.Errorf("host %q has no subdomain", host)
	}

	var firstLabel, rest string
	if i := strings.IndexByte(prefix, '.'); i >= 0 {
		firstLabel = prefix[:i]
		rest = prefix[i:]
	} else {
		firstLabel = prefix
	}

	if strings.HasSuffix(firstLabel, previewSuffix) {
		stripped := strings.TrimSuffix(firstLabel, previewSuffix)
		if stripped == "" {
			return "", "", fmt.Errorf("host %q has empty site label before preview suffix", host)
		}
		return stripped + rest + suffix, "preview", nil
	}

	return prefix + suffix, "production", nil
}
