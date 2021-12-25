import { App, RemoteBackend } from 'cdktf';

import prdMySQLDBStack from './prd/mysql-fs/';
import opsRGMachineImagesStack from './prd/resource-group/ops-rg-machine-images';

const app = new App();

const _prdMySQLDBStack = new prdMySQLDBStack(app, 'prd-stack-mysql-db');
new RemoteBackend(_prdMySQLDBStack, {
  hostname: 'app.terraform.io',
  organization: 'freecodecamp',
  workspaces: {
    name: 'tfws-prd-stack-mysql-db'
  }
});

const _opsRGMachineImagesStack = new opsRGMachineImagesStack(
  app,
  'ops-stack-machine-images'
);
new RemoteBackend(_opsRGMachineImagesStack, {
  hostname: 'app.terraform.io',
  organization: 'freecodecamp',
  workspaces: {
    name: 'tfws-ops-stack-machine-images'
  }
});

app.synth();
