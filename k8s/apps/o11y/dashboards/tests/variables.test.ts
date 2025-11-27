import { describe, test, expect } from 'vitest';
import { createLokiDatasourceVariable, createStackVariable } from '../src/builders/variables.js';
import { LokiVariableQueryType } from '../src/types.js';

describe('Variable Builders', () => {
  describe('createLokiDatasourceVariable', () => {
    test('should create Loki datasource variable', () => {
      const variable = createLokiDatasourceVariable().build();

      expect(variable.name).toBe('LOKI_DATASOURCE');
      expect(variable.type).toBe('datasource');
    });
  });

  describe('createStackVariable', () => {
    test('should create stack query variable with correct configuration', () => {
      const variable = createStackVariable().build();

      expect(variable.name).toBe('stack');
      expect(variable.query).toBeDefined();
    });

    test('should use LabelValues query type', () => {
      const variable = createStackVariable().build();
      const query = variable.query as {
        label: string;
        refId: string;
        stream: string;
        type: number;
      };

      expect(query.label).toBe('swarm_stack');
      expect(query.type).toBe(LokiVariableQueryType.LabelValues);
      expect(query.refId).toBe('LokiVariableQueryEditor-VariableQuery');
      expect(query.stream).toBe('');
    });
  });
});
