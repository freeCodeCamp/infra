import { App } from 'cdktf';

import { createRemoteBackends } from './components/remote-backend';

import prdMySQLDBStack from './prd/instances-mysql-flexible-server';
import opsRGMachineImagesStack from './prd/instances-resource-group/ops-rg-machine-images';
import opsRGCommonStack from './prd/instances-resource-group/ops-rg-common';

const app = new App();

createRemoteBackends(app, [
  {
    stackConstruct: opsRGCommonStack,
    stackName: 'common',
    stackConfig: { env: 'ops' }
  },
  {
    stackConstruct: opsRGMachineImagesStack,
    stackName: 'machine-images',
    stackConfig: { env: 'ops' }
  },
  {
    stackConstruct: prdMySQLDBStack,
    stackName: 'mysql-db',
    stackConfig: { env: 'prd' }
  }
]);

app.synth();
