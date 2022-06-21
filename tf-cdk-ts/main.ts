import { App } from 'cdktf';

import { createRemoteBackends } from './components/remote-backend';

// Operations Resources
import opsMachineImagesStack from './stacks-ops/machine-images';
import opsCommonStack from './stacks-ops/common';
// import opsGitHubRunnersStack from './stacks-ops/github-runners';

// Staging Resources
import stgMySQLDBStack from './stacks-stg/mysql-db';

// Production Resources
import prdMySQLDBStack from './stacks-prd/mysql-db';
// import prdWriteStack from './stacks-prd/write';

const app = new App();

createRemoteBackends(app, [
  // Operations Resources
  {
    stackConstruct: opsCommonStack,
    stackConfig: { env: 'ops', name: 'common', tlds: ['dev', 'org'] }
  },
  {
    stackConstruct: opsMachineImagesStack,
    stackConfig: { env: 'ops', name: 'machine-images' }
  },
  // {
  //   stackConstruct: opsGitHubRunnersStack,
  //   stackConfig: { env: 'ops', name: 'github-runners' }
  // },

  // Staging Resources
  {
    stackConstruct: stgMySQLDBStack,
    stackConfig: { env: 'stg', name: 'mysql-db' }
  },

  // Production Resources
  {
    stackConstruct: prdMySQLDBStack,
    stackConfig: { env: 'prd', name: 'mysql-db' }
  }
  // {
  //   stackConstruct: prdWriteStack,
  //   stackConfig: { env: 'prd', name: 'write' }
  // }
]);

app.synth();
