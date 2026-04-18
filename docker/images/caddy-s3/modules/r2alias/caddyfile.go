package r2alias

import (
	"strconv"
	"time"

	"github.com/caddyserver/caddy/v2/caddyconfig/caddyfile"
	"github.com/caddyserver/caddy/v2/caddyconfig/httpcaddyfile"
	"github.com/caddyserver/caddy/v2/modules/caddyhttp"
)

// parseCaddyfile is the directive registration entry point. It allocates a
// new R2Alias, invokes UnmarshalCaddyfile, and returns the configured handler.
// Called by the Caddyfile adapter when it encounters `r2_alias { ... }`.
func parseCaddyfile(h httpcaddyfile.Helper) (caddyhttp.MiddlewareHandler, error) {
	r := new(R2Alias)
	if err := r.UnmarshalCaddyfile(h.Dispenser); err != nil {
		return nil, err
	}
	return r, nil
}

// UnmarshalCaddyfile populates the R2Alias struct from Caddyfile tokens.
//
// Grammar:
//
//	r2_alias {
//	    bucket <str>
//	    endpoint <str>
//	    region <str>
//	    access_key_id <str>
//	    secret_access_key <str>
//	    cache_ttl <duration>
//	    cache_max_entries <int>
//	    preview_suffix <str>
//	    root_domain <str>
//	    deploy_id_regex <str>
//	}
//
// Every sub-directive accepts exactly one argument. Unknown tokens are rejected
// so typos surface at config-parse time, not at request time.
func (r *R2Alias) UnmarshalCaddyfile(d *caddyfile.Dispenser) error {
	for d.Next() {
		if d.NextArg() {
			return d.ArgErr()
		}
		for d.NextBlock(0) {
			switch d.Val() {
			case "bucket":
				if !d.NextArg() {
					return d.ArgErr()
				}
				r.Bucket = d.Val()
			case "endpoint":
				if !d.NextArg() {
					return d.ArgErr()
				}
				r.Endpoint = d.Val()
			case "region":
				if !d.NextArg() {
					return d.ArgErr()
				}
				r.Region = d.Val()
			case "access_key_id":
				if !d.NextArg() {
					return d.ArgErr()
				}
				r.AccessKeyID = d.Val()
			case "secret_access_key":
				if !d.NextArg() {
					return d.ArgErr()
				}
				r.SecretAccessKey = d.Val()
			case "cache_ttl":
				if !d.NextArg() {
					return d.ArgErr()
				}
				dur, err := time.ParseDuration(d.Val())
				if err != nil {
					return d.Errf("cache_ttl: %v", err)
				}
				r.CacheTTL = dur
			case "cache_max_entries":
				if !d.NextArg() {
					return d.ArgErr()
				}
				n, err := strconv.Atoi(d.Val())
				if err != nil {
					return d.Errf("cache_max_entries: %v", err)
				}
				r.CacheMaxEntries = n
			case "preview_suffix":
				if !d.NextArg() {
					return d.ArgErr()
				}
				r.PreviewSuffix = d.Val()
			case "root_domain":
				if !d.NextArg() {
					return d.ArgErr()
				}
				r.RootDomain = d.Val()
			case "deploy_id_regex":
				if !d.NextArg() {
					return d.ArgErr()
				}
				r.DeployIDRegex = d.Val()
			default:
				return d.Errf("unknown r2_alias sub-directive: %s", d.Val())
			}
		}
	}
	return nil
}
