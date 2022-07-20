import { App } from 'cdktf';

import { createRemoteBackends } from './components/remote-backend';

// Operations Resources
import opsMachineImagesStack from './stacks-ops/machine-images';
import opsCommonStack from './stacks-ops/common';
// import opsGitHubRunnersStack from './stacks-ops/github-runners';

// Staging Resources
// import stgMySQLDBStack from './stacks-stg/mysql-db';
import stgClusterServerStack from './stacks-stg/cluster-servers';
import stgClusterClientStack from './stacks-stg/cluster-clients';

// Production Resources
// import prdMySQLDBStack from './stacks-prd/mysql-db';

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
    stackConstruct: stgClusterServerStack,
    stackConfig: { env: 'stg', name: 'dc-servers' }
  },
  {
    stackConstruct: stgClusterClientStack,
    stackConfig: { env: 'stg', name: 'dc-clients' }
  }
  // {
  //   stackConstruct: stgMySQLDBStack,
  //   stackConfig: { env: 'stg', name: 'mysql-db' }
  // }

  // Production Resources
  // {
  //   stackConstruct: prdMySQLDBStack,
  //   stackConfig: { env: 'prd', name: 'mysql-db' }
  // }
]);

app.synth();
