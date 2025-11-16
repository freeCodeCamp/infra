import { describe, test, expect } from 'vitest';
import { LokiQueryBuilder } from '../src/builders/queries.js';
import { DatasourceRef } from '../src/types.js';

describe('LokiQueryBuilder', () => {
  const baseLabels = { service: 'api', swarm_stack: 'production' };
  const datasource: DatasourceRef = { type: 'loki', uid: 'test-loki' };

  describe('constructor and label selector', () => {
    test('should build correct label selector with multiple labels', () => {
      const builder = new LokiQueryBuilder(baseLabels);
      const query = builder.totalRequests('A', '5m').build();
      expect(query.expr).toContain('service="api"');
      expect(query.expr).toContain('swarm_stack="production"');
    });

    test('should handle empty base labels', () => {
      const builder = new LokiQueryBuilder({});
      const query = builder.totalRequests('A', '5m').build();
      expect(query.expr).toContain('{}');
    });

    test('should set datasource when provided', () => {
      const builder = new LokiQueryBuilder(baseLabels, datasource);
      const query = builder.totalRequests('A', '5m').build();
      expect(query.datasource).toEqual(datasource);
    });

    test('should not set datasource when not provided', () => {
      const builder = new LokiQueryBuilder(baseLabels);
      const query = builder.totalRequests('A', '5m').build();
      expect(query.datasource).toBeUndefined();
    });
  });

  describe('totalRequests', () => {
    test('should generate valid total requests query', () => {
      const builder = new LokiQueryBuilder(baseLabels);
      const query = builder.totalRequests('A', '$__range').build();

      expect(query.expr).toContain('sum(count_over_time(');
      expect(query.expr).toContain('| json');
      expect(query.expr).toContain('__error__=""');
      expect(query.expr).toContain('[$__range]');
      expect(query.refId).toBe('A');
      expect(query.legendFormat).toBe('Total Requests');
    });
  });

  describe('requestRate', () => {
    test('should generate valid request rate query', () => {
      const builder = new LokiQueryBuilder(baseLabels);
      const query = builder.requestRate('B', '$__interval').build();

      expect(query.expr).toContain('sum(rate(');
      expect(query.expr).toContain('[$__interval]');
      expect(query.refId).toBe('B');
      expect(query.legendFormat).toBe('Request Rate (RPS)');
    });
  });

  describe('latencyPercentile', () => {
    test('should generate valid P95 query with aggregation to prevent series limit', () => {
      const builder = new LokiQueryBuilder(baseLabels);
      const query = builder.latencyPercentile(0.95, 'A', '$__interval', 'p95').build();

      expect(query.expr).toContain('quantile_over_time(0.95,');
      expect(query.expr).toContain('avg by()');
      expect(query.expr).toContain('unwrap res_RES_ELAPSED_TIME');
      expect(query.expr).toContain('/ 1000');
      expect(query.legendFormat).toBe('p95');
    });

    test('should generate valid P99 query', () => {
      const builder = new LokiQueryBuilder(baseLabels);
      const query = builder.latencyPercentile(0.99, 'C', '$__interval', 'p99').build();

      expect(query.expr).toContain('quantile_over_time(0.99,');
      expect(query.expr).toContain('avg by()');
      expect(query.refId).toBe('C');
      expect(query.legendFormat).toBe('p99');
    });

    test('should use default legend format when not provided', () => {
      const builder = new LokiQueryBuilder(baseLabels);
      const query = builder.latencyPercentile(0.5).build();

      expect(query.legendFormat).toBe('p50');
    });
  });

  describe('requestsByStatusRange', () => {
    test('should generate valid 2xx query with vector(0)', () => {
      const builder = new LokiQueryBuilder(baseLabels);
      const query = builder.requestsByStatusRange(200, 300, 'A', '$__range', '2xx', true).build();

      expect(query.expr).toContain('res_RES_STATUS_CODE >= 200');
      expect(query.expr).toContain('res_RES_STATUS_CODE < 300');
      expect(query.expr).toContain('or vector(0)');
      expect(query.legendFormat).toBe('2xx');
    });

    test('should generate valid 5xx query without vector(0)', () => {
      const builder = new LokiQueryBuilder(baseLabels);
      const query = builder
        .requestsByStatusRange(500, 600, 'C', '$__interval', '5xx', false)
        .build();

      expect(query.expr).toContain('res_RES_STATUS_CODE >= 500');
      expect(query.expr).toContain('res_RES_STATUS_CODE < 600');
      expect(query.expr).not.toContain('or vector(0)');
      expect(query.legendFormat).toBe('5xx');
    });

    test('should use default legend format when not provided', () => {
      const builder = new LokiQueryBuilder(baseLabels);
      const query = builder.requestsByStatusRange(400, 500).build();

      expect(query.legendFormat).toBe('400-500');
    });

    test('should use pipeline filters instead of and operator', () => {
      const builder = new LokiQueryBuilder(baseLabels);
      const query = builder.requestsByStatusRange(200, 300).build();

      // Should use pipeline | for sequential filtering, not 'and'
      expect(query.expr).toContain('| res_RES_STATUS_CODE >= 200 | res_RES_STATUS_CODE < 300 |');
      expect(query.expr).not.toContain('and');
    });
  });

  describe('topKByPath', () => {
    test('should generate valid top 10 query with regex to strip query params', () => {
      const builder = new LokiQueryBuilder(baseLabels);
      const query = builder.topKByPath(10, 'A', '$__range').build();

      expect(query.expr).toContain('topk(10,');
      expect(query.expr).toContain('sum by (clean_path)');
      expect(query.expr).toContain('regexReplaceAll "\\\\?.*" .url ""');
      expect(query.expr).toContain('count_over_time(');
      expect(query.instant).toBe(true);
      expect(query.legendFormat).toBe('{{clean_path}}');
    });

    test('should respect k parameter', () => {
      const builder = new LokiQueryBuilder(baseLabels);
      const query = builder.topKByPath(5, 'A', '$__range').build();

      expect(query.expr).toContain('topk(5,');
    });
  });

  describe('topKSlowestByPath', () => {
    test('should generate valid slowest endpoints query', () => {
      const builder = new LokiQueryBuilder(baseLabels);
      const query = builder.topKSlowestByPath(10, 'A', '$__range').build();

      expect(query.expr).toContain('topk(10,');
      expect(query.expr).toContain('quantile_over_time(0.95,');
      expect(query.expr).toContain('regexReplaceAll "\\\\?.*" .url ""');
      expect(query.expr).toContain('unwrap res_RES_ELAPSED_TIME');
      expect(query.expr).toContain('/ 1000');
      expect(query.instant).toBe(true);
    });
  });

  describe('errorRatePercentage', () => {
    test('should generate valid error rate query', () => {
      const builder = new LokiQueryBuilder(baseLabels);
      const query = builder.errorRatePercentage('A', '$__interval').build();

      expect(query.expr).toContain('res_RES_STATUS_CODE >= 400');
      expect(query.expr).toContain('* 100');
      expect(query.legendFormat).toBe('Error Rate %');
    });

    test('should support offset parameter', () => {
      const builder = new LokiQueryBuilder(baseLabels);
      const query = builder.errorRatePercentage('A', '$__interval', '1h').build();

      expect(query.expr).toContain('offset 1h');
    });
  });

  describe('averageLatency', () => {
    test('should generate valid average latency query with aggregation', () => {
      const builder = new LokiQueryBuilder(baseLabels);
      const query = builder.averageLatency('A', '$__interval').build();

      expect(query.expr).toContain('avg_over_time(');
      expect(query.expr).toContain('avg by()');
      expect(query.expr).toContain('unwrap res_RES_ELAPSED_TIME');
      expect(query.expr).toContain('/ 1000');
      expect(query.legendFormat).toBe('Avg Latency (ms)');
    });
  });

  describe('rawLogs', () => {
    test('should generate valid raw logs query', () => {
      const builder = new LokiQueryBuilder(baseLabels);
      const query = builder.rawLogs('A', 1000).build();

      expect(query.expr).toContain('| json');
      expect(query.expr).toContain('service="api"');
      expect(query.maxLines).toBe(1000);
    });

    test('should use default maxLines when not provided', () => {
      const builder = new LokiQueryBuilder(baseLabels);
      const query = builder.rawLogs('A').build();

      expect(query.maxLines).toBe(1000);
    });
  });
});
