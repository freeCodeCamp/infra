package r2alias

import (
	"fmt"
	"strings"
)

// parseSiteAndAlias extracts (site, alias) from a Host header.
//
// The preview suffix is recognized ONLY on the leftmost label — an inner
// label that ends in `--preview` is part of the site name. The returned
// site always uses the production subdomain because preview and production
// share the same {site}/deploys/{id}/* prefix in R2; only the alias file
// differs.
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
