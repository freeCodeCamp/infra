import {
  DashboardBuilder,
  ThresholdsConfigBuilder,
  ThresholdsMode,
  Dashboard as GrafanaDashboard
} from '@grafana/grafana-foundation-sdk/dashboard';
import { PanelBuilder as StatPanelBuilder } from '@grafana/grafana-foundation-sdk/stat';
import { PanelBuilder as TimeSeriesPanelBuilder } from '@grafana/grafana-foundation-sdk/timeseries';
import { PanelBuilder as TablePanelBuilder } from '@grafana/grafana-foundation-sdk/table';
import { PanelBuilder as LogsPanelBuilder } from '@grafana/grafana-foundation-sdk/logs';
import {
  BigValueGraphMode,
  BigValueColorMode,
  LogsSortOrder,
  ReduceDataOptionsBuilder,
  VizLegendOptionsBuilder,
  VizTooltipOptionsBuilder,
  VizTextDisplayOptionsBuilder,
  LegendDisplayMode,
  LegendPlacement,
  TooltipDisplayMode,
  SortOrder
} from '@grafana/grafana-foundation-sdk/common';
import { LokiQueryBuilder } from '../builders/queries.js';
import { createStackVariable } from '../builders/variables.js';
import { DatasourceRef } from '../types.js';

export function createAPIMonitoringDashboard(): GrafanaDashboard {
  // Reference Loki datasource by name
  const datasourceRef: DatasourceRef = {
    type: 'loki',
    uid: 'Loki'
  };

  const queryBuilder = new LokiQueryBuilder(
    {
      service: 'api',
      swarm_stack: '$stack'
    },
    datasourceRef
  );

  // Helper functions for common builder patterns
  const createReduceOptions = () =>
    new ReduceDataOptionsBuilder().values(false).calcs(['lastNotNull']).fields('');

  const createThresholds = (steps: Array<{ color: string; value: number | null }>) =>
    new ThresholdsConfigBuilder().mode(ThresholdsMode.Absolute).steps(steps);

  const createStatTextOptions = () =>
    new VizTextDisplayOptionsBuilder().valueSize(40).percentSize(10);

  const createListLegend = () =>
    new VizLegendOptionsBuilder()
      .showLegend(true)
      .displayMode(LegendDisplayMode.List)
      .placement(LegendPlacement.Bottom)
      .calcs(['lastNotNull', 'max', 'mean']);

  const createTooltip = () =>
    new VizTooltipOptionsBuilder().mode(TooltipDisplayMode.Multi).sort(SortOrder.None);

  // Build dashboard using SDK
  const dashboard = new DashboardBuilder('freeCodeCamp API Dashboard')
    .uid('freecodecamp-api-v1')
    .tags(['API', 'Docker', 'Loki'])
    .timezone('utc')
    .refresh('5m')
    .time({ from: 'now-1h', to: 'now' })
    .editable()

    // Add variables
    .withVariable(createStackVariable())

    // Row 1: Stat panels - Total Requests, Request Rate, P95, P99, 2xx, 4xx, 5xx
    .withPanel(
      new StatPanelBuilder()
        .title('Total Requests')
        .gridPos({ x: 0, y: 0, w: 5, h: 4 })
        .datasource(datasourceRef)
        .withTarget(queryBuilder.totalRequests('A', '$__range'))
        .unit('short')
        .graphMode(BigValueGraphMode.None)
        .colorMode(BigValueColorMode.Value)
        .wideLayout(true)
        .showPercentChange(true)
        .text(createStatTextOptions())
        .reduceOptions(createReduceOptions())
        .thresholds(createThresholds([{ color: 'green', value: 0 }]))
    )

    .withPanel(
      new StatPanelBuilder()
        .title('Request Rate (RPS)')
        .gridPos({ x: 5, y: 0, w: 4, h: 4 })
        .datasource(datasourceRef)
        .withTarget(queryBuilder.requestRate('A', '$__range'))
        .unit('reqps')
        .graphMode(BigValueGraphMode.None)
        .colorMode(BigValueColorMode.Value)
        .wideLayout(true)
        .showPercentChange(true)
        .text(createStatTextOptions())
        .reduceOptions(createReduceOptions())
        .thresholds(createThresholds([{ color: 'green', value: 0 }]))
    )

    .withPanel(
      new StatPanelBuilder()
        .title('2xx')
        .gridPos({ x: 9, y: 0, w: 3, h: 4 })
        .datasource(datasourceRef)
        .withTarget(queryBuilder.requestsByStatusRange(200, 300, 'A', '$__range', '2xx', true))
        .unit('short')
        .graphMode(BigValueGraphMode.None)
        .colorMode(BigValueColorMode.Value)
        .wideLayout(true)
        .showPercentChange(true)
        .text(createStatTextOptions())
        .reduceOptions(createReduceOptions())
        .thresholds(createThresholds([{ color: 'green', value: 0 }]))
    )

    .withPanel(
      new StatPanelBuilder()
        .title('4xx')
        .gridPos({ x: 12, y: 0, w: 3, h: 4 })
        .datasource(datasourceRef)
        .withTarget(queryBuilder.requestsByStatusRange(400, 500, 'A', '$__range', '4xx', true))
        .unit('short')
        .graphMode(BigValueGraphMode.None)
        .colorMode(BigValueColorMode.Value)
        .wideLayout(true)
        .showPercentChange(true)
        .text(createStatTextOptions())
        .reduceOptions(createReduceOptions())
        .thresholds(createThresholds([{ color: 'yellow', value: 0 }]))
    )

    .withPanel(
      new StatPanelBuilder()
        .title('5xx')
        .gridPos({ x: 15, y: 0, w: 3, h: 4 })
        .datasource(datasourceRef)
        .withTarget(queryBuilder.requestsByStatusRange(500, 600, 'A', '$__range', '5xx', true))
        .unit('short')
        .graphMode(BigValueGraphMode.None)
        .colorMode(BigValueColorMode.Value)
        .wideLayout(true)
        .showPercentChange(true)
        .text(createStatTextOptions())
        .reduceOptions(createReduceOptions())
        .thresholds(createThresholds([{ color: 'red', value: 0 }]))
    )

    .withPanel(
      new StatPanelBuilder()
        .title('P95')
        .gridPos({ x: 18, y: 0, w: 3, h: 4 })
        .datasource(datasourceRef)
        .withTarget(queryBuilder.latencyPercentile(0.95, 'A', '$__range', 'p95'))
        .unit('ms')
        .graphMode(BigValueGraphMode.None)
        .colorMode(BigValueColorMode.Value)
        .wideLayout(true)
        .showPercentChange(true)
        .text(createStatTextOptions())
        .reduceOptions(createReduceOptions())
        .thresholds(
          createThresholds([
            { color: 'green', value: 0 },
            { color: 'yellow', value: 100 },
            { color: 'red', value: 500 }
          ])
        )
    )

    .withPanel(
      new StatPanelBuilder()
        .title('P99')
        .gridPos({ x: 21, y: 0, w: 3, h: 4 })
        .datasource(datasourceRef)
        .withTarget(queryBuilder.latencyPercentile(0.99, 'A', '$__range', 'p99'))
        .unit('ms')
        .graphMode(BigValueGraphMode.None)
        .colorMode(BigValueColorMode.Value)
        .wideLayout(true)
        .showPercentChange(true)
        .text(createStatTextOptions())
        .reduceOptions(createReduceOptions())
        .thresholds(
          createThresholds([
            { color: 'green', value: 0 },
            { color: 'yellow', value: 200 },
            { color: 'red', value: 1000 }
          ])
        )
    )

    // Row 2: Requests by Status and Latency Percentiles
    .withPanel(
      new TimeSeriesPanelBuilder()
        .title('Requests by Status')
        .gridPos({ x: 0, y: 4, w: 12, h: 10 })
        .datasource(datasourceRef)
        .withTarget(
          queryBuilder.requestsByStatusRange(200, 300, 'A', '$__interval', 'Success (2xx)', true)
        )
        .withTarget(
          queryBuilder.requestsByStatusRange(
            400,
            500,
            'B',
            '$__interval',
            'Client Error (4xx)',
            true
          )
        )
        .withTarget(
          queryBuilder.requestsByStatusRange(
            500,
            600,
            'C',
            '$__interval',
            'Server Error (5xx)',
            true
          )
        )
        .unit('short')
        .legend(createListLegend())
        .tooltip(createTooltip())
        .overrideByName('Success (2xx)', [
          { id: 'color', value: { mode: 'fixed', fixedColor: 'green' } }
        ])
        .overrideByName('Client Error (4xx)', [
          { id: 'color', value: { mode: 'fixed', fixedColor: 'orange' } }
        ])
        .overrideByName('Server Error (5xx)', [
          { id: 'color', value: { mode: 'fixed', fixedColor: 'red' } }
        ])
    )

    .withPanel(
      new TimeSeriesPanelBuilder()
        .title('Latency Percentiles')
        .gridPos({ x: 12, y: 4, w: 12, h: 10 })
        .datasource(datasourceRef)
        .withTarget(queryBuilder.latencyPercentile(0.5, 'A', '$__interval', 'p50'))
        .withTarget(queryBuilder.latencyPercentile(0.95, 'B', '$__interval', 'p95'))
        .withTarget(queryBuilder.latencyPercentile(0.99, 'C', '$__interval', 'p99'))
        .unit('ms')
        .legend(createListLegend())
        .tooltip(createTooltip())
        .overrideByName('p50', [{ id: 'color', value: { mode: 'fixed', fixedColor: 'green' } }])
        .overrideByName('p95', [{ id: 'color', value: { mode: 'fixed', fixedColor: 'yellow' } }])
        .overrideByName('p99', [
          { id: 'color', value: { mode: 'fixed', fixedColor: 'red' } },
          { id: 'custom.lineWidth', value: 2 }
        ])
    )

    // Row 3: Top endpoints tables
    .withPanel(
      new TablePanelBuilder()
        .title('Top 10 Endpoints by Request Count')
        .gridPos({ x: 0, y: 14, w: 12, h: 12 })
        .datasource(datasourceRef)
        .withTarget(queryBuilder.topKByPath(10, 'A', '$__range'))
        .withTransformation({
          id: 'labelsToFields',
          options: { mode: 'columns', valueLabel: 'clean_path' }
        })
        .withTransformation({
          id: 'organize',
          options: {
            excludeByName: { Time: true },
            indexByName: {},
            renameByName: { clean_path: 'Endpoint', Value: 'Request Count' }
          }
        })
        .showHeader(true)
        .filterable(true)
    )

    .withPanel(
      new TablePanelBuilder()
        .title('Top 10 Slowest Endpoints (P95)')
        .gridPos({ x: 12, y: 14, w: 12, h: 12 })
        .datasource(datasourceRef)
        .withTarget(queryBuilder.topKSlowestByPath(10, 'A', '$__range'))
        .withTransformation({
          id: 'labelsToFields',
          options: { mode: 'columns', valueLabel: 'clean_path' }
        })
        .withTransformation({
          id: 'organize',
          options: {
            excludeByName: { Time: true },
            indexByName: {},
            renameByName: { clean_path: 'Endpoint', Value: 'P95 Latency (ms)' }
          }
        })
        .showHeader(true)
        .filterable(true)
    )

    // Row 4: Logs
    .withPanel(
      new LogsPanelBuilder()
        .title('Logs')
        .gridPos({ x: 0, y: 26, w: 24, h: 22 })
        .datasource(datasourceRef)
        .withTarget(queryBuilder.rawLogs('A'))
        .showTime(true)
        .showLabels(false)
        .wrapLogMessage(false)
        .enableLogDetails(false)
        .sortOrder(LogsSortOrder.Descending)
    );

  return dashboard.build();
}
