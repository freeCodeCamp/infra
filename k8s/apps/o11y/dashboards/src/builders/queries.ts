import { DataqueryBuilder } from '@grafana/grafana-foundation-sdk/loki';
import { DatasourceRef } from '../types.js';

export class LokiQueryBuilder {
  private baseLabels: Record<string, string>;
  private datasource: DatasourceRef | undefined;

  constructor(baseLabels: Record<string, string> = {}, datasource?: DatasourceRef) {
    this.baseLabels = baseLabels;
    this.datasource = datasource;
  }

  private setDatasourceIfProvided(builder: DataqueryBuilder): DataqueryBuilder {
    if (this.datasource) {
      return builder.datasource(this.datasource);
    }
    return builder;
  }

  private buildLabelSelector(): string {
    const labels = Object.entries(this.baseLabels)
      .map(([key, value]) => `${key}="${value}"`)
      .join(', ');
    return `{${labels}}`;
  }

  errorRatePercentage(refId: string = 'A', interval: string = '$__interval', offset?: string) {
    const selector = this.buildLabelSelector();
    const offsetStr = offset ? ` offset ${offset}` : '';
    const expr = `(
  sum(rate(${selector} | json | res_RES_STATUS_CODE >= 400 | __error__="" [${interval}]${offsetStr}))
  /
  sum(rate(${selector} | json | __error__="" [${interval}]${offsetStr}))
) * 100`;

    const builder = new DataqueryBuilder().expr(expr).refId(refId).legendFormat('Error Rate %');

    return this.setDatasourceIfProvided(builder);
  }

  latencyPercentile(
    percentile: number,
    refId: string = 'A',
    interval: string = '$__interval',
    legendFormat?: string
  ) {
    const selector = this.buildLabelSelector();
    const expr = `avg by() (quantile_over_time(${percentile}, ${selector} | json | unwrap res_RES_ELAPSED_TIME | __error__="" [${interval}])) / 1000`;

    const builder = new DataqueryBuilder()
      .expr(expr)
      .refId(refId)
      .legendFormat(legendFormat || `p${percentile * 100}`);

    return this.setDatasourceIfProvided(builder);
  }

  topKByPath(k: number, refId: string = 'A', interval: string = '$__interval') {
    const selector = this.buildLabelSelector();
    const expr = `topk(${k},
  sum by (clean_path) (
    count_over_time(
      ${selector}
      | json
      | label_format clean_path=\`{{regexReplaceAll "\\\\?.*" .url ""}}\`
      | __error__=""
      [${interval}]
    )
  )
)`;

    const builder = new DataqueryBuilder()
      .expr(expr)
      .refId(refId)
      .legendFormat('{{clean_path}}')
      .instant(true);

    return this.setDatasourceIfProvided(builder);
  }

  topKSlowestByPath(k: number, refId: string = 'A', interval: string = '$__interval') {
    const selector = this.buildLabelSelector();
    const expr = `topk(${k},
  quantile_over_time(0.95,
    ${selector}
    | json
    | label_format clean_path=\`{{regexReplaceAll "\\\\?.*" .url ""}}\`
    | unwrap res_RES_ELAPSED_TIME
    | __error__=""
    [${interval}]
  ) by (clean_path)
) / 1000`;

    const builder = new DataqueryBuilder()
      .expr(expr)
      .refId(refId)
      .legendFormat('{{clean_path}}')
      .instant(true);

    return this.setDatasourceIfProvided(builder);
  }

  requestsByStatusRange(
    minStatus: number,
    maxStatus: number,
    refId: string = 'A',
    interval: string = '$__interval',
    legendFormat?: string,
    showZeroWhenNoData: boolean = false
  ) {
    const selector = this.buildLabelSelector();
    const baseExpr = `sum(count_over_time(${selector} | json | res_RES_STATUS_CODE >= ${minStatus} | res_RES_STATUS_CODE < ${maxStatus} | __error__="" [${interval}]))`;
    const expr = showZeroWhenNoData ? `${baseExpr} or vector(0)` : baseExpr;

    const builder = new DataqueryBuilder()
      .expr(expr)
      .refId(refId)
      .legendFormat(legendFormat || `${minStatus}-${maxStatus}`);

    return this.setDatasourceIfProvided(builder);
  }

  totalRequests(refId: string = 'A', interval: string = '$__interval') {
    const selector = this.buildLabelSelector();
    const expr = `sum(count_over_time(${selector} | json | __error__="" [${interval}]))`;

    const builder = new DataqueryBuilder().expr(expr).refId(refId).legendFormat('Total Requests');

    return this.setDatasourceIfProvided(builder);
  }

  requestRate(refId: string = 'A', interval: string = '$__interval') {
    const selector = this.buildLabelSelector();
    const expr = `sum(rate(${selector} | json | __error__="" [${interval}]))`;

    const builder = new DataqueryBuilder()
      .expr(expr)
      .refId(refId)
      .legendFormat('Request Rate (RPS)');

    return this.setDatasourceIfProvided(builder);
  }

  averageLatency(refId: string = 'A', interval: string = '$__interval') {
    const selector = this.buildLabelSelector();
    // Use avg by() to aggregate all series into a single value
    const expr = `avg by() (avg_over_time(${selector} | json | unwrap res_RES_ELAPSED_TIME | __error__="" [${interval}])) / 1000`;

    const builder = new DataqueryBuilder().expr(expr).refId(refId).legendFormat('Avg Latency (ms)');

    return this.setDatasourceIfProvided(builder);
  }

  rawLogs(refId: string = 'A', maxLines: number = 1000) {
    const selector = this.buildLabelSelector();
    const expr = `${selector} | json`;

    const builder = new DataqueryBuilder().expr(expr).refId(refId).maxLines(maxLines);

    return this.setDatasourceIfProvided(builder);
  }
}
