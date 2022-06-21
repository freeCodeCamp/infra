import 'cdktf/lib/testing/adapters/jest'; // Load types for expect matchers
import { Testing } from 'cdktf';

import prdMySQLDBStack from '../stacks-prd/mysql-db';

// https://cdk.tf/testing
describe('News - Write Stack', () => {
  describe('Checking validity', () => {
    it('check if the produced terraform configuration is valid', () => {
      const app = Testing.app();
      const stack = new prdMySQLDBStack(app, 'mysql-db-test', {
        name: 'mysql-db-test',
        env: 'tst'
      });
      expect(Testing.fullSynth(stack)).toBeValidTerraform();
    });
    it('check if this can be planned', () => {
      const app = Testing.app();
      const stack = new prdMySQLDBStack(app, 'mysql-db-test', {
        name: 'mysql-db-test',
        env: 'tst'
      });
      expect(Testing.fullSynth(stack)).toPlanSuccessfully();
    });
  });
});
