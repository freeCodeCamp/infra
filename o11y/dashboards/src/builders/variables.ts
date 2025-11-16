import {
  DatasourceVariableBuilder,
  QueryVariableBuilder
} from '@grafana/grafana-foundation-sdk/dashboard';
import { LokiVariableQuery, LokiVariableQueryType } from '../types.js';

export function createLokiDatasourceVariable() {
  return new DatasourceVariableBuilder('LOKI_DATASOURCE').type('loki');
}

export function createStackVariable() {
  const query: LokiVariableQuery = {
    label: 'swarm_stack',
    refId: 'LokiVariableQueryEditor-VariableQuery',
    stream: '',
    type: LokiVariableQueryType.LabelValues
  };

  return new QueryVariableBuilder('stack').query(query);
}
