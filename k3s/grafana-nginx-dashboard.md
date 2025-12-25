# NGINX Logs Dashboard for Grafana

Dashboard panels for analyzing NGINX access logs stored in ClickHouse.

## Prerequisites

- Grafana deployed on ops-backoffice-tools cluster
- ClickHouse datasource configured:
  - **Server:** `clickhouse-egress.tailscale.svc.cluster.local`
  - **Port:** `8123` (HTTP)
  - **Username:** `grafana`
  - **Database:** `logs_nginx_stg` (staging) or `logs_nginx_prd` (production)

## Dashboard Structure

| Row | Section | Panels |
|-----|---------|--------|
| 1 | Key Metrics | Stats: Total Requests, Error Rate, P95 Latency, Real Traffic % |
| 2 | Traffic | Time series: Requests over time |
| 3 | Status Codes | Time series: Status distribution, Pie: Status breakdown |
| 4 | Latency | Time series: P50/P95/P99 percentiles |
| 5 | Endpoints | Tables: Top paths, Slowest endpoints |
| 6 | Geographic | Bar: Requests by country |

---

## Panel Queries

### Row 1: Key Metrics (Stat Panels)

**Total Requests**
```sql
SELECT count(*) AS total
FROM logs_nginx_stg.access
WHERE $__timeFilter(timestamp)
```

**Error Rate %**
```sql
SELECT round(countIf(status >= 400 AND status != 444) * 100.0 / count(), 2) AS error_rate
FROM logs_nginx_stg.access
WHERE $__timeFilter(timestamp)
```
- Thresholds: green < 1%, yellow < 5%, red >= 5%

**P95 Latency (ms)**
```sql
SELECT round(quantile(0.95)(request_time) * 1000, 2) AS p95_ms
FROM logs_nginx_stg.access
WHERE $__timeFilter(timestamp) AND request_time > 0
```
- Thresholds: green < 500ms, yellow < 1000ms, red >= 1000ms

**Real Traffic %**
```sql
SELECT round(countIf(cf_ray != '') * 100.0 / count(), 2) AS real_traffic_pct
FROM logs_nginx_stg.access
WHERE $__timeFilter(timestamp)
```
- Description: Traffic through Cloudflare (has cf_ray) vs direct/bot traffic

---

### Row 2: Traffic Over Time (Time Series)

**Requests per Minute**
```sql
SELECT
  toStartOfMinute(timestamp) AS time,
  count() AS requests
FROM logs_nginx_stg.access
WHERE $__timeFilter(timestamp)
GROUP BY time
ORDER BY time
```

**Requests by Host**
```sql
SELECT
  toStartOfMinute(timestamp) AS time,
  host,
  count() AS requests
FROM logs_nginx_stg.access
WHERE $__timeFilter(timestamp)
GROUP BY time, host
ORDER BY time
```

---

### Row 3: Status Code Analysis

**Status Codes Over Time (Time Series - Stacked)**
```sql
SELECT
  toStartOfMinute(timestamp) AS time,
  multiIf(
    status < 300, '2xx',
    status < 400, '3xx',
    status < 500, '4xx',
    status = 444, '444 blocked',
    '5xx'
  ) AS status_class,
  count() AS requests
FROM logs_nginx_stg.access
WHERE $__timeFilter(timestamp)
GROUP BY time, status_class
ORDER BY time
```

**Status Distribution (Pie Chart)**
```sql
SELECT
  multiIf(
    status < 300, '2xx Success',
    status < 400, '3xx Redirect',
    status < 500, '4xx Client Error',
    status = 444, '444 Blocked',
    '5xx Server Error'
  ) AS status_class,
  count() AS count
FROM logs_nginx_stg.access
WHERE $__timeFilter(timestamp)
GROUP BY status_class
ORDER BY count DESC
```

---

### Row 4: Latency Percentiles (Time Series)

**P50/P95/P99 Latency**
```sql
SELECT
  toStartOfMinute(timestamp) AS time,
  round(quantile(0.5)(request_time) * 1000, 2) AS p50,
  round(quantile(0.95)(request_time) * 1000, 2) AS p95,
  round(quantile(0.99)(request_time) * 1000, 2) AS p99
FROM logs_nginx_stg.access
WHERE $__timeFilter(timestamp) AND request_time > 0
GROUP BY time
ORDER BY time
```
- Y-axis unit: milliseconds (ms)

---

### Row 5: Endpoint Analysis (Tables)

**Top Endpoints by Request Count**
```sql
SELECT
  path,
  count() AS requests,
  round(avg(request_time) * 1000, 2) AS avg_ms,
  round(quantile(0.95)(request_time) * 1000, 2) AS p95_ms,
  countIf(status >= 400) AS errors
FROM logs_nginx_stg.access
WHERE $__timeFilter(timestamp)
GROUP BY path
ORDER BY requests DESC
LIMIT 20
```

**Slowest Endpoints (P95)**
```sql
SELECT
  path,
  count() AS requests,
  round(quantile(0.5)(request_time) * 1000, 2) AS p50_ms,
  round(quantile(0.95)(request_time) * 1000, 2) AS p95_ms,
  round(quantile(0.99)(request_time) * 1000, 2) AS p99_ms
FROM logs_nginx_stg.access
WHERE $__timeFilter(timestamp) AND request_time > 0
GROUP BY path
HAVING requests > 10
ORDER BY p95_ms DESC
LIMIT 20
```

**Top Error Paths**
```sql
SELECT
  path,
  status,
  count() AS error_count
FROM logs_nginx_stg.access
WHERE $__timeFilter(timestamp) AND status >= 400
GROUP BY path, status
ORDER BY error_count DESC
LIMIT 20
```

---

### Row 6: Geographic & Security

**Requests by Country (Bar Gauge)**
```sql
SELECT
  country_code,
  count() AS requests
FROM logs_nginx_stg.access
WHERE $__timeFilter(timestamp) AND country_code != ''
GROUP BY country_code
ORDER BY requests DESC
LIMIT 15
```

**Bot vs Real Traffic (Time Series)**
```sql
SELECT
  toStartOfMinute(timestamp) AS time,
  multiIf(
    cf_ray != '', 'Cloudflare (Real)',
    status = 444, 'Blocked (444)',
    'Direct/Bot'
  ) AS traffic_type,
  count() AS requests
FROM logs_nginx_stg.access
WHERE $__timeFilter(timestamp)
GROUP BY time, traffic_type
ORDER BY time
```

**SSL Protocol Distribution (Pie Chart)**
```sql
SELECT
  if(ssl_protocol = '', 'No SSL', ssl_protocol) AS protocol,
  count() AS count
FROM logs_nginx_stg.access
WHERE $__timeFilter(timestamp)
GROUP BY protocol
ORDER BY count DESC
```

---

## Dashboard Variables

Add these template variables for filtering:

| Variable | Label | Query | Multi |
|----------|-------|-------|-------|
| `host` | Host | `SELECT DISTINCT host FROM logs_nginx_stg.access WHERE timestamp >= now() - INTERVAL 1 DAY ORDER BY host` | Yes |
| `status` | Status | `SELECT DISTINCT status FROM logs_nginx_stg.access WHERE timestamp >= now() - INTERVAL 1 DAY ORDER BY status` | Yes |
| `country` | Country | `SELECT DISTINCT country_code FROM logs_nginx_stg.access WHERE timestamp >= now() - INTERVAL 1 DAY AND country_code != '' ORDER BY country_code` | Yes |

Use in queries: `AND host IN ($host)` or `AND status IN ($status)`

---

## Alert Recommendations

| Metric | Warning | Critical |
|--------|---------|----------|
| Error Rate (5xx) | > 1% | > 5% |
| P95 Latency | > 500ms | > 1000ms |
| P99 Latency | > 1000ms | > 2000ms |
| Blocked Rate (444) | > 10% | > 25% |

---

## Notes

- **Staging database:** `logs_nginx_stg.access`
- **Production database:** `logs_nginx_prd.access`
- **Data retention:** 15 days
- **Partitioning:** Monthly (`toYYYYMM(date)`)
- **Status 444:** NGINX closed connection without response (blocked/invalid requests)
- **cf_ray:** Present indicates traffic through Cloudflare (legitimate)

See [nginx-logs-schema.md](nginx-logs-schema.md) for full schema details.
