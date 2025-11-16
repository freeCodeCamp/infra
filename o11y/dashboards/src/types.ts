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
