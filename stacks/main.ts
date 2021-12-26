import { App } from 'cdktf';

import { createRemoteBackends } from './components/remote-backend';

import prdMySQLDBStack from './prd/instances-mysql-flexible-server';
import opsRGMachineImagesStack from './prd/instances-resource-group/ops-rg-machine-images';
import opsRGCommonStack from './prd/instances-resource-group/ops-rg-common';

const app = new App();

createRemoteBackends(app, [
  { stackConstruct: opsRGCommonStack, stackName: 'ops-rg-common' },
  {
    stackConstruct: opsRGMachineImagesStack,
    stackName: 'ops-rg-machine-images'
  },
  { stackConstruct: prdMySQLDBStack, stackName: 'prd-mysql-db' }
]);

app.synth();
