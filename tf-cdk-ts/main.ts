import { App } from 'cdktf';

import { createRemoteBackends } from './components/remote-backend';

// Operations Resources
import opsMachineImagesStack from './stacks-ops/machine-images';
import opsCommonStack from './stacks-ops/common';
import opsGitHubRunnersStack from './stacks-ops/github-runners';

// Production Resources
import prdMySQLDBStack from './stacks-prd/mysql-db';
import prdWriteStack from './stacks-prd/write';

const app = new App();

createRemoteBackends(app, [
  // Operations Resources
  {
    stackConstruct: opsCommonStack,
    stackName: 'common',
    stackConfig: { env: 'ops', tlds: ['dev', 'org'] }
  },
  {
    stackConstruct: opsMachineImagesStack,
    stackName: 'machine-images',
    stackConfig: { env: 'ops' }
  },
  {
    stackConstruct: opsGitHubRunnersStack,
    stackName: 'github-runners',
    stackConfig: { env: 'ops' }
  },

  // Production Resources
  {
    stackConstruct: prdMySQLDBStack,
    stackName: 'mysql-db',
    stackConfig: { env: 'prd' }
  },
  {
    stackConstruct: prdWriteStack,
    stackName: 'write',
    stackConfig: { env: 'prd' }
  }
]);

app.synth();
