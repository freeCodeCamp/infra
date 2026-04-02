# NGINX Logs Schema Documentation

## Databases

| Database | Table | Environment |
|----------|-------|-------------|
| `logs_nginx_stg` | `access` | Staging |
| `logs_nginx_prd` | `access` | Production |

## NGINX JSON Log Format

Log file: `/var/log/nginx/json_access.log`

Format name: `json_analytics` (defined in [nginx-config repo](https://github.com/freeCodeCamp/nginx-config))

**Sample log entry:**
```json
{
  "msec": "1735041330.123",
  "request_method": "GET",
  "request_uri": "/learn/javascript",
  "args": "",
  "status": "200",
  "bytes_sent": "12345",
  "request_time": "0.052",
  "http_host": "www.freecodecamp.org",
  "remote_addr": "192.168.1.1",
  "http_user_agent": "Mozilla/5.0...",
  "http_cf_ray": "abc123",
  "geoip_country_code": "US"
}
```

## ClickHouse Schema Mapping

| NGINX JSON Field | ClickHouse Column | Type | Notes |
|------------------|-------------------|------|-------|
| `msec` | `timestamp` | DateTime64(3) | Unix timestamp |
| - | `date` | Date | Derived from timestamp |
| `request_method` | `method` | LowCardinality(String) | GET, POST, etc. |
| `request_uri` | `path` | String | URL path |
| `args` | `query_string` | String | Query parameters |
| `server_protocol` | `protocol` | LowCardinality(String) | HTTP/1.1, HTTP/2 |
| `scheme` | `scheme` | LowCardinality(String) | http, https |
| `status` | `status` | UInt16 | HTTP status code |
| `bytes_sent` | `bytes_sent` | UInt64 | Total bytes sent |
| `body_bytes_sent` | `body_bytes_sent` | UInt64 | Body bytes only |
| `request_length` | `request_length` | UInt32 | Request size |
| `request_time` | `request_time` | Float32 | Total request time |
| `upstream_response_time` | `upstream_response_time` | Float32 | Backend time |
| `upstream_connect_time` | `upstream_connect_time` | Float32 | Connect time |
| `upstream_header_time` | `upstream_header_time` | Float32 | Header time |
| `remote_addr` | `remote_addr` | String | Client IP |
| `remote_user` | `remote_user` | String | Basic auth user |
| `http_host` | `host` | LowCardinality(String) | Request Host header |
| `server_name` | `server_name` | LowCardinality(String) | NGINX server_name |
| `http_user_agent` | `user_agent` | String | Browser/client |
| `http_referer` | `referer` | String | Referrer URL |
| `http_x_forwarded_for` | `x_forwarded_for` | String | Original client IP |
| `upstream` | `upstream_addr` | String | Backend server |
| `upstream_cache_status` | `upstream_cache_status` | LowCardinality(String) | HIT, MISS, etc. |
| `ssl_protocol` | `ssl_protocol` | LowCardinality(String) | TLSv1.2, TLSv1.3 |
| `ssl_cipher` | `ssl_cipher` | LowCardinality(String) | Cipher suite |
| `http_cf_ray` | `cf_ray` | String | Cloudflare Ray ID |
| `geoip_country_code` | `country_code` | LowCardinality(String) | Country code |
| `request_id` | `request_id` | String | Request tracing ID |
| - | `source_host` | LowCardinality(String) | Vector host |
| - | `source_file` | LowCardinality(String) | Log file path |

## Schema Features

- **Compression:** ZSTD level 3 for strings, Delta for timestamps
- **Partitioning:** Monthly (`toYYYYMM(date)`)
- **Ordering:** `(host, timestamp)` for efficient time-range queries per domain
- **TTL:** 15 days automatic deletion
- **Replication:** 3 replicas across nodes

## Vector Filtering

Filtered out before ingestion:
- Health check endpoints (`/health`, `/.well-known`)
- Kubernetes probes (`kube-probe` user agent)
- Load balancer health checks (`ELB-HealthChecker`, `DigitalOcean`)

## Sample Queries

Replace `logs_nginx_prd` with `logs_nginx_stg` for staging.

```sql
-- Requests per minute
SELECT toStartOfMinute(timestamp) AS minute, count() AS requests
FROM logs_nginx_prd.access
WHERE timestamp > now() - INTERVAL 1 HOUR
GROUP BY minute ORDER BY minute;

-- Top paths
SELECT path, count() AS requests, avg(request_time) AS avg_time
FROM logs_nginx_prd.access
WHERE date = today()
GROUP BY path ORDER BY requests DESC LIMIT 20;

-- Error rate
SELECT status, count() AS count,
       round(count() * 100.0 / sum(count()) OVER (), 2) AS pct
FROM logs_nginx_prd.access
WHERE date = today()
GROUP BY status ORDER BY count DESC;

-- Slow requests (> 1s)
SELECT timestamp, host, path, request_time
FROM logs_nginx_prd.access
WHERE request_time > 1
ORDER BY timestamp DESC LIMIT 100;

-- By country
SELECT country_code, count() AS requests
FROM logs_nginx_prd.access
WHERE date = today() AND country_code != ''
GROUP BY country_code ORDER BY requests DESC LIMIT 20;

-- Cache hit ratio
SELECT upstream_cache_status, count() AS count
FROM logs_nginx_prd.access
WHERE date = today() AND upstream_cache_status != ''
GROUP BY upstream_cache_status ORDER BY count DESC;
```
