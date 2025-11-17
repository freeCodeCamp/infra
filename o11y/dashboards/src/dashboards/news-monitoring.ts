import {
  DashboardBuilder,
  ThresholdsConfigBuilder,
  ThresholdsMode,
  Dashboard as GrafanaDashboard
} from '@grafana/grafana-foundation-sdk/dashboard';
import { PanelBuilder as StatPanelBuilder } from '@grafana/grafana-foundation-sdk/stat';
import { PanelBuilder as TimeSeriesPanelBuilder } from '@grafana/grafana-foundation-sdk/timeseries';
import { PanelBuilder as LogsPanelBuilder } from '@grafana/grafana-foundation-sdk/logs';
import { DataqueryBuilder } from '@grafana/grafana-foundation-sdk/loki';
import {
  BigValueGraphMode,
  BigValueColorMode,
  BigValueTextMode,
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
import { createLokiDatasourceVariable } from '../builders/variables.js';
import { DatasourceRef } from '../types.js';

export function createNewsMonitoringDashboard(): GrafanaDashboard {
  // Use the oncall-specific Loki datasource directly
  const datasourceRef: DatasourceRef = {
    type: 'loki',
    uid: 'ff42fx0hl5qtcd'
  };

  const newsServices = ['chn', 'esp', 'ita', 'jpn', 'kor', 'por', 'ukr'];
  const serviceLabels: Record<string, string> = {
    chn: 'Chinese',
    esp: 'Español',
    ita: 'Italian',
    jpn: 'Japanese',
    kor: 'Korean',
    por: 'Portuguese',
    ukr: 'Ukrainian'
  };

  // Helper functions
  const createReduceOptions = () =>
    new ReduceDataOptionsBuilder().values(false).calcs(['lastNotNull']).fields('');

  const createThresholds = (steps: Array<{ color: string; value: number | null }>) =>
    new ThresholdsConfigBuilder().mode(ThresholdsMode.Absolute).steps(steps);

  const createStatTextOptions = () =>
    new VizTextDisplayOptionsBuilder().valueSize(32).titleSize(12);

  const createListLegend = () =>
    new VizLegendOptionsBuilder()
      .showLegend(true)
      .displayMode(LegendDisplayMode.List)
      .placement(LegendPlacement.Bottom);

  const createTooltip = () =>
    new VizTooltipOptionsBuilder().mode(TooltipDisplayMode.Multi).sort(SortOrder.None);

  const createQuery = (
    expr: string,
    refId: string,
    legendFormat?: string,
    maxLines?: number
  ): DataqueryBuilder => {
    const builder = new DataqueryBuilder().datasource(datasourceRef).expr(expr).refId(refId);

    if (legendFormat) {
      builder.legendFormat(legendFormat);
    }

    if (maxLines !== undefined) {
      builder.maxLines(maxLines);
    }

    return builder;
  };

  const dashboard = new DashboardBuilder('freeCodeCamp News Dashboard (Gantry)')
    .uid('freecodecamp-news-v1')
    .tags(['News', 'Docker', 'Loki'])
    .description('Monitor automated news service updates via Gantry (runs hourly at :45)')
    .timezone('utc')
    .refresh('15m')
    .time({ from: 'now-2d', to: 'now' })
    .editable()

    // Variables
    .withVariable(createLokiDatasourceVariable())

    // Row 1: Executive Summary
    .withPanel(
      new StatPanelBuilder()
        .title('Total Log Lines')
        .description('Total Gantry log activity in selected range')
        .gridPos({ x: 0, y: 0, w: 6, h: 5 })
        .datasource(datasourceRef)
        .withTarget(
          createQuery('sum(count_over_time({stack="oncall", service="update"} [$__range]))', 'A')
        )
        .unit('short')
        .graphMode(BigValueGraphMode.Area)
        .colorMode(BigValueColorMode.Value)
        .textMode(BigValueTextMode.ValueAndName)
        .text(createStatTextOptions())
        .reduceOptions(createReduceOptions())
        .thresholds(createThresholds([{ color: 'blue', value: 0 }]))
    )

    .withPanel(
      new StatPanelBuilder()
        .title('Service Updates')
        .description('Number of service update operations in selected range')
        .gridPos({ x: 6, y: 0, w: 6, h: 5 })
        .datasource(datasourceRef)
        .withTarget(
          createQuery(
            'sum(count_over_time({stack="oncall", service="update"} |~ "(?i)updating" [$__range]))',
            'A'
          )
        )
        .unit('short')
        .graphMode(BigValueGraphMode.Area)
        .colorMode(BigValueColorMode.Value)
        .textMode(BigValueTextMode.ValueAndName)
        .text(createStatTextOptions())
        .reduceOptions(createReduceOptions())
        .thresholds(createThresholds([{ color: 'green', value: 0 }]))
    )

    .withPanel(
      new StatPanelBuilder()
        .title('Successes')
        .description('Successful update operations')
        .gridPos({ x: 12, y: 0, w: 6, h: 5 })
        .datasource(datasourceRef)
        .withTarget(
          createQuery(
            'sum(count_over_time({stack="oncall", service="update"} |~ "(?i)updated" [$__range]))',
            'A'
          )
        )
        .unit('short')
        .graphMode(BigValueGraphMode.None)
        .colorMode(BigValueColorMode.Value)
        .textMode(BigValueTextMode.ValueAndName)
        .text(createStatTextOptions())
        .reduceOptions(createReduceOptions())
        .thresholds(createThresholds([{ color: 'green', value: 0 }]))
    )

    .withPanel(
      new StatPanelBuilder()
        .title('Failures & Rollbacks')
        .description('Failed updates and rollback events')
        .gridPos({ x: 18, y: 0, w: 6, h: 5 })
        .datasource(datasourceRef)
        .withTarget(
          createQuery(
            'sum(count_over_time({stack="oncall", service="update"} |~ "(?i)(fail|error|rollback)" [$__range])) or vector(0)',
            'A'
          )
        )
        .unit('short')
        .graphMode(BigValueGraphMode.None)
        .colorMode(BigValueColorMode.Value)
        .textMode(BigValueTextMode.ValueAndName)
        .text(createStatTextOptions())
        .reduceOptions(createReduceOptions())
        .thresholds(
          createThresholds([
            { color: 'green', value: 0 },
            { color: 'yellow', value: 1 },
            { color: 'red', value: 5 }
          ])
        )
    );

  // Row 2: Service Status Grid (7 services)
  let xPos = 0;
  newsServices.forEach(service => {
    const width = 3; // Reduced width to fit more panels
    const height = 4;

    dashboard.withPanel(
      new StatPanelBuilder()
        .title(`${serviceLabels[service]}`)
        .description(`Update activity for svc-${service}`)
        .gridPos({ x: xPos, y: 5, w: width, h: height })
        .datasource(datasourceRef)
        .withTarget(
          createQuery(
            `sum(count_over_time({stack="oncall", service="update"} |~ "(?i)svc-${service}" [$__range]))`,
            'A'
          )
        )
        .unit('short')
        .graphMode(BigValueGraphMode.Area)
        .colorMode(BigValueColorMode.Value)
        .textMode(BigValueTextMode.ValueAndName)
        .text(new VizTextDisplayOptionsBuilder().valueSize(20))
        .reduceOptions(createReduceOptions())
        .thresholds(
          createThresholds([
            { color: 'red', value: 0 },
            { color: 'yellow', value: 1 },
            { color: 'green', value: 3 }
          ])
        )
    );

    xPos += width;
    if (xPos >= 21) {
      xPos = 0;
    }
  });

  // Add final panel to fill the row
  dashboard
    .withPanel(
      new StatPanelBuilder()
        .title('Total Services')
        .description('Services tracked')
        .gridPos({ x: 21, y: 5, w: 3, h: 4 })
        .datasource(datasourceRef)
        .withTarget(createQuery('vector(7)', 'A'))
        .unit('short')
        .graphMode(BigValueGraphMode.None)
        .colorMode(BigValueColorMode.Value)
        .textMode(BigValueTextMode.Value)
        .text(new VizTextDisplayOptionsBuilder().valueSize(24))
        .reduceOptions(createReduceOptions())
        .thresholds(createThresholds([{ color: 'blue', value: 0 }]))
    )

    // Row 3: Update Activity by Service Name
    .withPanel(
      new TimeSeriesPanelBuilder()
        .title('Updates by Service Name (Extracted from Logs)')
        .description('Which news services are being updated')
        .gridPos({ x: 0, y: 9, w: 24, h: 8 })
        .datasource(datasourceRef)
        .withTarget(
          createQuery(
            'sum by (svc) (count_over_time({stack="oncall", service="update"} | regexp `svc-(?P<svc>\\w+)` [$__interval]))',
            'A',
            '{{svc}}'
          )
        )
        .unit('short')
        .legend(createListLegend())
        .tooltip(createTooltip())
    )

    // Row 4: Update Operations Timeline
    .withPanel(
      new TimeSeriesPanelBuilder()
        .title('Update Operations Over Time')
        .description('Count of update operations (updating, updated, failed, rollback)')
        .gridPos({ x: 0, y: 17, w: 12, h: 8 })
        .datasource(datasourceRef)
        .withTarget(
          createQuery(
            'sum(count_over_time({stack="oncall", service="update"} |~ "(?i)(updating service)" [$__interval]))',
            'A',
            'Starting Update'
          )
        )
        .withTarget(
          createQuery(
            'sum(count_over_time({stack="oncall", service="update"} |~ "(?i)(updated service|update succeed)" [$__interval]))',
            'B',
            'Success'
          )
        )
        .withTarget(
          createQuery(
            'sum(count_over_time({stack="oncall", service="update"} |~ "(?i)(fail|error)" [$__interval]))',
            'C',
            'Failed'
          )
        )
        .withTarget(
          createQuery(
            'sum(count_over_time({stack="oncall", service="update"} |~ "(?i)(rollback)" [$__interval]))',
            'D',
            'Rollback'
          )
        )
        .unit('short')
        .legend(createListLegend())
        .tooltip(createTooltip())
        .overrideByName('Starting Update', [
          { id: 'color', value: { mode: 'fixed', fixedColor: 'blue' } }
        ])
        .overrideByName('Success', [{ id: 'color', value: { mode: 'fixed', fixedColor: 'green' } }])
        .overrideByName('Failed', [{ id: 'color', value: { mode: 'fixed', fixedColor: 'red' } }])
        .overrideByName('Rollback', [
          { id: 'color', value: { mode: 'fixed', fixedColor: 'orange' } }
        ])
    )

    .withPanel(
      new TimeSeriesPanelBuilder()
        .title('Updates by News Service')
        .description('Which news services are being updated most frequently')
        .gridPos({ x: 12, y: 17, w: 12, h: 8 })
        .datasource(datasourceRef)
        .withTarget(
          createQuery(
            'sum by (svc) (count_over_time({stack="oncall", service="update"} | regexp `prd-news_svc-(?P<svc>\\w+)` [$__interval]))',
            'A',
            '{{svc}}'
          )
        )
        .unit('short')
        .legend(createListLegend())
        .tooltip(createTooltip())
    )

    // Row 5: Failures & Rollbacks
    .withPanel(
      new LogsPanelBuilder()
        .title('Failures & Rollbacks (Problems Only)')
        .description('Showing only failed updates and rollback events')
        .gridPos({ x: 0, y: 25, w: 24, h: 10 })
        .datasource(datasourceRef)
        .withTarget(
          createQuery(
            '{stack="oncall", service="update"} |~ "(?i)(fail|rollback|roll back|exception)" != "0 error" !~ "PARSE RATE ERROR"',
            'A',
            undefined,
            5000
          )
        )
        .showTime(true)
        .showLabels(true)
        .wrapLogMessage(true)
        .enableLogDetails(true)
        .sortOrder(LogsSortOrder.Descending)
    )

    // Row 6: All Update Logs
    .withPanel(
      new LogsPanelBuilder()
        .title('Logs')
        .description('Filtered logs showing service update operations')
        .gridPos({ x: 0, y: 35, w: 24, h: 12 })
        .datasource(datasourceRef)
        .withTarget(createQuery('{stack="oncall", service="update"}', 'A', undefined, 5000))
        .showTime(true)
        .showLabels(false)
        .wrapLogMessage(false)
        .enableLogDetails(true)
        .sortOrder(LogsSortOrder.Descending)
    );

  return dashboard.build();
}
