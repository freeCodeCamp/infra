/**
 * Simple Declarative Dashboard Builder
 *
 * TDD-friendly, minimal boilerplate approach to building Grafana dashboards.
 * Wraps Foundation SDK with sensible defaults and validation.
 */

import {
  DashboardBuilder,
  type Dashboard as GrafanaDashboard
} from '@grafana/grafana-foundation-sdk/dashboard';
import { PanelBuilder as StatPanelBuilder } from '@grafana/grafana-foundation-sdk/stat';
import { PanelBuilder as TablePanelBuilder } from '@grafana/grafana-foundation-sdk/table';
import { PanelBuilder as LogsPanelBuilder } from '@grafana/grafana-foundation-sdk/logs';
import { PanelBuilder as BarGaugePanelBuilder } from '@grafana/grafana-foundation-sdk/bargauge';
import { DataqueryBuilder } from '@grafana/grafana-foundation-sdk/loki';
import type { DatasourceRef } from '../types.js';

/**
 * Simple query definition
 */
export interface SimpleQuery {
  /** LogQL query expression */
  loki: string;
  /** Legend label for query results */
  label?: string;
  /** Query reference ID (auto-assigned if not provided: A, B, C, ...) */
  refId?: string;
}

/**
 * Grid position for panels
 */
export interface GridPosition {
  x: number;
  y: number;
  w: number;
  h: number;
}

/**
 * Simple panel definition
 */
export interface SimplePanel {
  /** Panel title */
  title: string;
  /** Panel type */
  type: 'stat' | 'table' | 'logs' | 'bargauge' | 'timeline';
  /** Grid position (auto-assigned if not provided) */
  grid?: GridPosition;
  /** Queries to execute */
  queries: SimpleQuery[];
  /** Panel-specific options */
  options?: Record<string, unknown>;
  /** Panel description */
  description?: string;
}

/**
 * Simple dashboard definition
 */
export interface SimpleDashboard {
  /** Unique dashboard identifier */
  uid: string;
  /** Dashboard title */
  title: string;
  /** Tags for organization */
  tags?: string[];
  /** Dashboard description */
  description?: string;
  /** Dashboard panels */
  panels: SimplePanel[];
  /** Refresh interval (default: '5m') */
  refresh?: string;
  /** Time range (default: { from: 'now-1h', to: 'now' }) */
  time?: { from: string; to: string };
}

/**
 * Auto-assign refIds to queries if not provided
 */
function assignRefIds(queries: SimpleQuery[]): SimpleQuery[] {
  return queries.map((q, i) => ({
    ...q,
    refId: q.refId || String.fromCharCode(65 + i) // A, B, C, ...
  }));
}

/**
 * Auto-layout panels with sensible defaults
 */
function autoLayout(panels: SimplePanel[]): SimplePanel[] {
  let currentY = 0;

  return panels.map(panel => {
    if (panel.grid) return panel;

    // Default heights based on panel type
    const heightMap: Record<string, number> = {
      logs: 22,
      table: 10,
      stat: 8,
      bargauge: 8,
      timeline: 8
    };

    const defaultHeight = heightMap[panel.type] || 8;
    const grid = { x: 0, y: currentY, w: 24, h: defaultHeight };
    currentY += defaultHeight;

    return { ...panel, grid };
  });
}

/**
 * Convert simple panel to Grafana Foundation SDK panel
 */
export function createPanel(
  config: SimplePanel,
  datasource: DatasourceRef
): StatPanelBuilder | TablePanelBuilder | LogsPanelBuilder | BarGaugePanelBuilder {
  const queries = assignRefIds(config.queries);
  const grid = config.grid || { x: 0, y: 0, w: 24, h: 8 };

  // Create base panel based on type
  let builder: StatPanelBuilder | TablePanelBuilder | LogsPanelBuilder | BarGaugePanelBuilder;

  if (config.type === 'stat') {
    builder = new StatPanelBuilder();
  } else if (config.type === 'table') {
    builder = new TablePanelBuilder();
  } else if (config.type === 'logs') {
    builder = new LogsPanelBuilder();
  } else if (config.type === 'bargauge') {
    builder = new BarGaugePanelBuilder();
  } else {
    throw new Error(`Unsupported panel type: ${config.type}`);
  }

  // Set common properties
  builder.title(config.title).gridPos(grid).datasource(datasource);

  if (config.description) {
    builder.description(config.description);
  }

  // Add queries
  queries.forEach(q => {
    builder.withTarget(
      new DataqueryBuilder()
        .datasource(datasource)
        .expr(q.loki)
        .refId(q.refId!)
        .legendFormat(q.label || '')
    );
  });

  return builder;
}

/**
 * Convert simple dashboard to Grafana dashboard
 */
export function createDashboard(
  config: SimpleDashboard,
  datasource: DatasourceRef
): GrafanaDashboard {
  const layouted = autoLayout(config.panels);

  const builder = new DashboardBuilder(config.title)
    .uid(config.uid)
    .tags(config.tags || [])
    .description(config.description || '')
    .refresh(config.refresh || '5m')
    .time(config.time || { from: 'now-1h', to: 'now' })
    .editable();

  layouted.forEach(p => {
    builder.withPanel(createPanel(p, datasource));
  });

  return builder.build();
}
