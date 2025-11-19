import {
  DashboardBuilder,
  ThresholdsConfigBuilder,
  ThresholdsMode,
  Dashboard as GrafanaDashboard
} from '@grafana/grafana-foundation-sdk/dashboard';
import { PanelBuilder as StatPanelBuilder } from '@grafana/grafana-foundation-sdk/stat';
import { PanelBuilder as BarGaugePanelBuilder } from '@grafana/grafana-foundation-sdk/bargauge';
import { PanelBuilder as LogsPanelBuilder } from '@grafana/grafana-foundation-sdk/logs';
import { PanelBuilder as TablePanelBuilder } from '@grafana/grafana-foundation-sdk/table';
import { PanelBuilder as StateTimelinePanelBuilder } from '@grafana/grafana-foundation-sdk/statetimeline';
import { DataqueryBuilder } from '@grafana/grafana-foundation-sdk/loki';
import {
  BigValueColorMode,
  BigValueGraphMode,
  BigValueTextMode,
  LogsSortOrder,
  ReduceDataOptionsBuilder,
  BarGaugeDisplayMode,
  BarGaugeNamePlacement,
  BarGaugeSizing,
  BarGaugeValueMode,
  VizLegendOptionsBuilder,
  VizOrientation,
  LegendDisplayMode
} from '@grafana/grafana-foundation-sdk/common';
import { DatasourceRef } from '../types.js';

export function createNewsMonitoringDashboard(): GrafanaDashboard {
  // Reference Loki - OnCall datasource by name
  const datasourceRef: DatasourceRef = {
    type: 'loki',
    uid: 'Loki - OnCall'
  };

  const dashboard = new DashboardBuilder('News Dashboard (Gantry)')
    .uid('freecodecamp-news-v1')
    .tags(['News', 'Docker', 'Loki'])
    .description('Monitor automated news service updates via Gantry (runs hourly at :45)')
    .timezone('utc')
    .refresh('15m')
    .time({ from: 'now-24h', to: 'now' })
    .editable()

    // Services Panel - shows Skipped and Updated counts
    .withPanel(
      new StatPanelBuilder()
        .title('Services')
        .gridPos({ x: 0, y: 0, w: 24, h: 9 })
        .datasource(datasourceRef)
        .withTarget(
          new DataqueryBuilder()
            .datasource(datasourceRef)
            .expr(
              'sum(count_over_time({stack="oncall", service="update"} |= `Skip updating` [$__range]))'
            )
            .refId('A')
            .legendFormat('Skipped')
        )
        .withTarget(
          new DataqueryBuilder()
            .datasource(datasourceRef)
            .expr(
              'sum(count_over_time({stack="oncall", service="update"} |= `Perform updating` [$__range]))'
            )
            .refId('B')
            .legendFormat('Updated')
        )
        .unit('short')
        .colorMode(BigValueColorMode.BackgroundSolid)
        .graphMode(BigValueGraphMode.None)
        .textMode(BigValueTextMode.ValueAndName)
        .orientation(VizOrientation.Vertical)
        .wideLayout(false)
        .reduceOptions(
          new ReduceDataOptionsBuilder().values(false).calcs(['lastNotNull']).fields('')
        )
        .thresholds(
          new ThresholdsConfigBuilder()
            .mode(ThresholdsMode.Absolute)
            .steps([{ color: 'green', value: null }])
        )
    )

    // Last Action Table - shows precise timestamps and counts per service
    .withPanel(
      new TablePanelBuilder()
        .title('Last Action by Service')
        .description('Timestamps of last update/skip per service with activity counts')
        .gridPos({ x: 0, y: 9, w: 24, h: 10 })
        .datasource(datasourceRef)
        // Last update timestamp per service
        .withTarget(
          new DataqueryBuilder()
            .datasource(datasourceRef)
            .expr(
              'last_over_time({stack="oncall", service="update"} |= "Perform updating" | regexp `prd-news_svc-(?P<svc>\\w+)` | line_format "{{.svc}}" [$__range]) by (svc)'
            )
            .refId('A')
            .legendFormat('{{svc}}')
        )
        // Last skip timestamp per service
        .withTarget(
          new DataqueryBuilder()
            .datasource(datasourceRef)
            .expr(
              'last_over_time({stack="oncall", service="update"} |= "Skip updating" | regexp `prd-news_svc-(?P<svc>\\w+)` | line_format "{{.svc}}" [$__range]) by (svc)'
            )
            .refId('B')
            .legendFormat('{{svc}}')
        )
        // Update count in time window
        .withTarget(
          new DataqueryBuilder()
            .datasource(datasourceRef)
            .expr(
              'sum by (svc) (count_over_time({stack="oncall", service="update"} |= "Perform updating" | regexp `prd-news_svc-(?P<svc>\\w+)` [$__range]))'
            )
            .refId('C')
            .legendFormat('{{svc}}')
        )
        // Skip count in time window
        .withTarget(
          new DataqueryBuilder()
            .datasource(datasourceRef)
            .expr(
              'sum by (svc) (count_over_time({stack="oncall", service="update"} |= "Skip updating" | regexp `prd-news_svc-(?P<svc>\\w+)` [$__range]))'
            )
            .refId('D')
            .legendFormat('{{svc}}')
        )
        .withTransformation({
          id: 'merge',
          options: {}
        })
        .withTransformation({
          id: 'organize',
          options: {
            renameByName: {
              'Value #A': 'Last Updated',
              'Value #B': 'Last Skipped',
              'Value #C': 'Updates',
              'Value #D': 'Skips'
            },
            indexByName: {
              svc: 0,
              'Value #A': 1,
              'Value #B': 2,
              'Value #C': 3,
              'Value #D': 4
            }
          }
        })
        .showHeader(true)
    )

    // State Timeline - visual activity over time
    .withPanel(
      new StateTimelinePanelBuilder()
        .title('Service Activity Timeline')
        .description(
          'Visual timeline showing when services were updated (green) or skipped (yellow)'
        )
        .gridPos({ x: 0, y: 19, w: 24, h: 8 })
        .datasource(datasourceRef)
        .withTarget(
          new DataqueryBuilder()
            .datasource(datasourceRef)
            .expr(
              'sum by (svc, action) (count_over_time({stack="oncall", service="update"} | regexp `prd-news_svc-(?P<svc>\\w+)` | line_format "{{.svc}}" | __line__ |~ "(?P<action>Perform updating|Skip updating)" [1m]))'
            )
            .refId('A')
            .legendFormat('{{svc}}')
        )
        .withTransformation({
          id: 'renameByRegex',
          options: {
            regex: 'prd-news_svc-(\\w+)',
            renamePattern: '$1'
          }
        })
        .legend(new VizLegendOptionsBuilder().showLegend(true).displayMode(LegendDisplayMode.List))
    )

    // Stale Service Alert - shows time since last update
    .withPanel(
      new StatPanelBuilder()
        .title('Minutes Since Last Update')
        .description('Time since any service was last updated (red if >120min)')
        .gridPos({ x: 0, y: 27, w: 8, h: 6 })
        .datasource(datasourceRef)
        .withTarget(
          new DataqueryBuilder()
            .datasource(datasourceRef)
            .expr(
              '(time() - last_over_time({stack="oncall", service="update"} |= "Perform updating" [24h] offset 0s)) / 60'
            )
            .refId('A')
            .legendFormat('Minutes')
        )
        .unit('m')
        .colorMode(BigValueColorMode.Background)
        .graphMode(BigValueGraphMode.None)
        .textMode(BigValueTextMode.ValueAndName)
        .reduceOptions(
          new ReduceDataOptionsBuilder().values(false).calcs(['lastNotNull']).fields('')
        )
        .thresholds(
          new ThresholdsConfigBuilder().mode(ThresholdsMode.Absolute).steps([
            { color: 'green', value: 0 },
            { color: 'yellow', value: 60 },
            { color: 'red', value: 120 }
          ])
        )
    )

    // Update/Skip Ratio - overall health metric
    .withPanel(
      new StatPanelBuilder()
        .title('Update vs Skip Ratio')
        .description('Overall distribution of updates vs skips across all services')
        .gridPos({ x: 8, y: 27, w: 16, h: 6 })
        .datasource(datasourceRef)
        .withTarget(
          new DataqueryBuilder()
            .datasource(datasourceRef)
            .expr(
              'sum(count_over_time({stack="oncall", service="update"} |= "Perform updating" [$__range]))'
            )
            .refId('A')
            .legendFormat('Updated')
        )
        .withTarget(
          new DataqueryBuilder()
            .datasource(datasourceRef)
            .expr(
              'sum(count_over_time({stack="oncall", service="update"} |= "Skip updating" [$__range]))'
            )
            .refId('B')
            .legendFormat('Skipped')
        )
        .unit('short')
        .colorMode(BigValueColorMode.Value)
        .graphMode(BigValueGraphMode.None)
        .textMode(BigValueTextMode.ValueAndName)
        .orientation(VizOrientation.Horizontal)
        .reduceOptions(
          new ReduceDataOptionsBuilder().values(false).calcs(['lastNotNull']).fields('')
        )
        .thresholds(
          new ThresholdsConfigBuilder().mode(ThresholdsMode.Absolute).steps([
            { color: 'blue', value: 0 },
            { color: 'green', value: 1 }
          ])
        )
    )

    // Image Deletion Success Panel - counts successful image deletions by service
    .withPanel(
      new BarGaugePanelBuilder()
        .title('Image Deletions (Successful)')
        .description('Successful image removals by service (by 3-letter code)')
        .gridPos({ x: 0, y: 33, w: 12, h: 8 })
        .datasource(datasourceRef)
        .withTarget(
          new DataqueryBuilder()
            .datasource(datasourceRef)
            .expr(
              'sum by (svc) (count_over_time({stack="oncall", service="update"} |= "Removed image" | regexp `news-(?P<svc>\\w+):` [$__range]))'
            )
            .refId('A')
            .legendFormat('{{svc}}')
        )
        .unit('short')
        .reduceOptions(
          new ReduceDataOptionsBuilder().values(false).calcs(['lastNotNull']).fields('')
        )
        .withTransformation({
          id: 'sortBy',
          options: {
            sort: [{ field: 'Value #A', desc: true }]
          }
        })
        .thresholds(
          new ThresholdsConfigBuilder()
            .mode(ThresholdsMode.Absolute)
            .steps([{ color: 'green', value: null }])
        )
        .orientation(VizOrientation.Horizontal)
        .displayMode(BarGaugeDisplayMode.Lcd)
        .valueMode(BarGaugeValueMode.Text)
        .namePlacement(BarGaugeNamePlacement.Left)
        .showUnfilled(true)
        .sizing(BarGaugeSizing.Manual)
        .minVizWidth(8)
        .minVizHeight(50)
        .maxVizHeight(250)
        .legend(new VizLegendOptionsBuilder().showLegend(false))
    )

    // Image Deletion Skipped Panel - counts when no images were removed
    .withPanel(
      new StatPanelBuilder()
        .title('Image Deletions (Skipped)')
        .description('Times when no images needed removal')
        .gridPos({ x: 12, y: 33, w: 12, h: 8 })
        .datasource(datasourceRef)
        .withTarget(
          new DataqueryBuilder()
            .datasource(datasourceRef)
            .expr(
              'sum(count_over_time({stack="oncall", service="update"} |= "No images to remove" [$__range]))'
            )
            .refId('A')
            .legendFormat('Skipped')
        )
        .unit('short')
        .colorMode(BigValueColorMode.Background)
        .graphMode(BigValueGraphMode.None)
        .reduceOptions(
          new ReduceDataOptionsBuilder().values(false).calcs(['lastNotNull']).fields('')
        )
        .thresholds(
          new ThresholdsConfigBuilder()
            .mode(ThresholdsMode.Absolute)
            .steps([{ color: 'text', value: 0 }])
        )
    )

    // Logs Panel - shows all update logs
    .withPanel(
      new LogsPanelBuilder()
        .title('Logs')
        .description('Filtered logs showing service update operations')
        .gridPos({ x: 0, y: 41, w: 24, h: 22 })
        .datasource(datasourceRef)
        .withTarget(
          new DataqueryBuilder()
            .datasource(datasourceRef)
            .expr('{stack="oncall", service="update"}')
            .refId('A')
            .maxLines(5000)
        )
        .showTime(true)
        .showLabels(false)
        .wrapLogMessage(false)
        .enableLogDetails(true)
        .sortOrder(LogsSortOrder.Descending)
    );

  return dashboard.build();
}
