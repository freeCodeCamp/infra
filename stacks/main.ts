import { App, RemoteBackend } from 'cdktf';

import prdMySQLDBStack from './prd/mysql-fs/';
import opsRGMachineImagesStack from './prd/resource-group/ops-rg-machine-images';

const app = new App();

const _prdMySQLDBStack = new prdMySQLDBStack(app, 'prd-stack-mysql-db');
// const _opsRGMachineImagesStack = new opsRGMachineImagesStack(
new opsRGMachineImagesStack(app, 'ops-stack-machine-images');

new RemoteBackend(_prdMySQLDBStack, {
  hostname: 'app.terraform.io',
  organization: 'freecodecamp',
  workspaces: {
    name: 'tfws_ts_stacks'
  }
});

app.synth();
