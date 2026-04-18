package r2alias

import (
	"testing"
)

// TestParseSiteAndAlias_TableDriven covers the full grammar per RFC §4.3.7:
// preview is identified by a `--preview` suffix on the LEFTMOST label only;
// the preview site key is always the production subdomain (deploys are shared
// between production and preview — only the alias file differs).
func TestParseSiteAndAlias_TableDriven(t *testing.T) {
	t.Parallel()

	const (
		rootDomain    = "freecode.camp"
		previewSuffix = "--preview"
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
			name:      "single-label preview",
			host:      "hello-world--preview.freecode.camp",
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
			name:    "empty site label before preview suffix",
			host:    "--preview.freecode.camp",
			wantErr: true,
		},
	}

	for _, c := range cases {
		c := c
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			site, alias, err := parseSiteAndAlias(c.host, rootDomain, previewSuffix)
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

// TestParseSiteAndAlias_PreviewOnNonLeftmostLabel asserts the preview suffix
// is recognized ONLY on the leftmost label. A `--preview` suffix on any
// inner label is part of the site name, not an alias indicator.
func TestParseSiteAndAlias_PreviewOnNonLeftmostLabel(t *testing.T) {
	t.Parallel()
	site, alias, err := parseSiteAndAlias("foo.bar--preview.freecode.camp", "freecode.camp", "--preview")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if site != "foo.bar--preview.freecode.camp" {
		t.Errorf("site should retain inner --preview: got %q", site)
	}
	if alias != "production" {
		t.Errorf("alias should be production (preview suffix on inner label does not count): got %q", alias)
	}
}
