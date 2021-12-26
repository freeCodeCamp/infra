import { App, RemoteBackend } from 'cdktf';

import prdMySQLDBStack from './prd/instances-mysql-flexible-server';
import opsRGMachineImagesStack from './prd/instances-resource-group/ops-rg-machine-images';
import opsRGCommonStack from './prd/instances-resource-group/ops-rg-common';

const app = new App();

// Operations - Machine Images
const _opsRGCommonStack = new opsRGCommonStack(app, 'ops-stack-common');
new RemoteBackend(_opsRGCommonStack, {
  hostname: 'app.terraform.io',
  organization: 'freecodecamp',
  workspaces: {
    name: 'tfws-ops-stack-common'
  }
});

// Operations - Machine Images
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

// Production - MySQL DB (Flexible Server) DB Cluster
const _prdMySQLDBStack = new prdMySQLDBStack(app, 'prd-stack-mysql-db');
new RemoteBackend(_prdMySQLDBStack, {
  hostname: 'app.terraform.io',
  organization: 'freecodecamp',
  workspaces: {
    name: 'tfws-prd-stack-mysql-db'
  }
});

app.synth();
