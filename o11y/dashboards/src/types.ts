export interface DatasourceRef {
  type: string;
  uid: string;
}

export enum LokiVariableQueryType {
  LabelValues = 1,
  LabelNames = 2
}

export interface LokiVariableQuery {
  label: string;
  refId: string;
  stream: string;
  type: LokiVariableQueryType;
}

// Grafana panel types for post-processing JSON output
export interface FieldConfigDefaults {
  color?: {
    mode: string;
  };
  [key: string]: unknown;
}

export interface FieldConfig {
  defaults: FieldConfigDefaults;
  overrides?: unknown[];
}

export interface GrafanaPanel {
  title?: string;
  type?: string;
  fieldConfig?: FieldConfig;
  [key: string]: unknown;
}

export interface GrafanaDashboardJSON {
  panels?: GrafanaPanel[];
  [key: string]: unknown;
}
