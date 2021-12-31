import { App } from 'cdktf';

import { createRemoteBackends } from './components/remote-backend';

// Operations Resources
import opsMachineImagesStack from './ops/machine-images';
import opsCommonStack from './ops/common';
import opsGitHubRunnersStack from './ops/github-runners';

// Production Resources
import prdMySQLDBStack from './prd/mysql-db';
import prdWriteStack from './prd/write';

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
