-- Create logs_nginx_prd database (production)
CREATE DATABASE IF NOT EXISTS logs_nginx_prd ON CLUSTER '{cluster}';

-- NGINX access logs table (JSON format from json_analytics)
CREATE TABLE IF NOT EXISTS logs_nginx_prd.access ON CLUSTER '{cluster}'
(
    timestamp DateTime64(3) CODEC(Delta, ZSTD(3)),
    date Date DEFAULT toDate(timestamp),

    -- Request info
    method LowCardinality(String),
    path String CODEC(ZSTD(3)),
    query_string String CODEC(ZSTD(3)),
    protocol LowCardinality(String),
    scheme LowCardinality(String),
    status UInt16,

    -- Size and timing
    bytes_sent UInt64,
    body_bytes_sent UInt64,
    request_length UInt32,
    request_time Float32,
    upstream_response_time Float32,
    upstream_connect_time Float32,
    upstream_header_time Float32,

    -- Client info
    remote_addr String CODEC(ZSTD(3)),
    remote_user String CODEC(ZSTD(3)),

    -- Headers
    host LowCardinality(String),
    server_name LowCardinality(String),
    user_agent String CODEC(ZSTD(3)),
    referer String CODEC(ZSTD(3)),
    x_forwarded_for String CODEC(ZSTD(3)),

    -- Upstream
    upstream_addr String CODEC(ZSTD(3)),
    upstream_cache_status LowCardinality(String),

    -- SSL/TLS
    ssl_protocol LowCardinality(String),
    ssl_cipher LowCardinality(String),

    -- Cloudflare
    cf_ray String CODEC(ZSTD(3)),
    country_code LowCardinality(String),

    -- Tracing
    request_id String CODEC(ZSTD(3)),

    -- Source metadata
    source_host LowCardinality(String),
    source_file LowCardinality(String)
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/logs_nginx_prd/access', '{replica}')
PARTITION BY toYYYYMM(date)
ORDER BY (host, timestamp)
TTL date + INTERVAL 15 DAY
SETTINGS index_granularity = 8192;
