package r2alias

import (
	"testing"
)

// Dot-scheme: preview routing keys off the rightmost label of the site
// prefix being equal to a configured `preview` subdomain (D35 supersedes
// D5). Hostname `<labels>.preview.<root>` resolves to site
// `<labels>.<root>` with alias=preview. Anywhere else, the `preview`
// token is part of the site name and routing falls through to production.
func TestParseSiteAndAlias_TableDriven(t *testing.T) {
	t.Parallel()

	const (
		rootDomain       = "freecode.camp"
		previewSubdomain = "preview"
	)

	cases := []struct {
		name      string
		host      string
		wantSite  string
		wantAlias string
		wantErr   bool
	}{
		{
			name:      "single-label production",
			host:      "hello-world.freecode.camp",
			wantSite:  "hello-world.freecode.camp",
			wantAlias: "production",
		},
		{
			name:      "single-label preview (dot-scheme)",
			host:      "hello-world.preview.freecode.camp",
			wantSite:  "hello-world.freecode.camp",
			wantAlias: "preview",
		},
		{
			name:      "multi-label production",
			host:      "foo.bar.freecode.camp",
			wantSite:  "foo.bar.freecode.camp",
			wantAlias: "production",
		},
		{
			name:      "multi-label preview (dot-scheme)",
			host:      "foo.bar.preview.freecode.camp",
			wantSite:  "foo.bar.freecode.camp",
			wantAlias: "preview",
		},
		{
			name:    "non-root domain rejected",
			host:    "other.com",
			wantErr: true,
		},
		{
			name:    "apex rejected",
			host:    "freecode.camp",
			wantErr: true,
		},
		{
			name:    "preview-only apex (no site label) rejected",
			host:    "preview.freecode.camp",
			wantErr: true,
		},
	}

	for _, c := range cases {
		c := c
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			site, alias, err := parseSiteAndAlias(c.host, rootDomain, previewSubdomain)
			if c.wantErr {
				if err == nil {
					t.Fatalf("parseSiteAndAlias(%q) = (%q, %q, nil), want error", c.host, site, alias)
				}
				return
			}
			if err != nil {
				t.Fatalf("parseSiteAndAlias(%q) unexpected error: %v", c.host, err)
			}
			if site != c.wantSite {
				t.Errorf("site: want %q, got %q", c.wantSite, site)
			}
			if alias != c.wantAlias {
				t.Errorf("alias: want %q, got %q", c.wantAlias, alias)
			}
		})
	}
}

// `preview` only triggers preview routing when it is the RIGHTMOST label
// of the prefix (i.e. immediately before the root domain). An inner
// `preview` label is part of the site name and routes to production.
func TestParseSiteAndAlias_PreviewOnInnerLabel(t *testing.T) {
	t.Parallel()
	site, alias, err := parseSiteAndAlias("foo.preview.bar.freecode.camp", "freecode.camp", "preview")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if site != "foo.preview.bar.freecode.camp" {
		t.Errorf("site should retain inner preview label: got %q", site)
	}
	if alias != "production" {
		t.Errorf("alias should be production (inner preview does not count): got %q", alias)
	}
}

// A site label literally named `preview` (e.g. `preview.something.preview.freecode.camp`)
// is permitted — the rightmost-label rule still applies. The leftmost
// `preview` is part of the site name; the rightmost is the alias trigger.
func TestParseSiteAndAlias_SiteLabelNamedPreview(t *testing.T) {
	t.Parallel()
	site, alias, err := parseSiteAndAlias("preview.preview.freecode.camp", "freecode.camp", "preview")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if site != "preview.freecode.camp" {
		t.Errorf("site: want %q, got %q", "preview.freecode.camp", site)
	}
	if alias != "preview" {
		t.Errorf("alias: want %q, got %q", "preview", alias)
	}
}
