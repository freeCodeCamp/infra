import { App, RemoteBackend } from 'cdktf';

import fCCPrdMySQLDBStack from './prd/mysql-fs/';

const app = new App();
const stack = new fCCPrdMySQLDBStack(app, 'prd-stack-mysql-db');

new RemoteBackend(stack, {
  hostname: 'app.terraform.io',
  organization: 'freecodecamp',
  workspaces: {
    name: 'tfws_ts_stacks'
  }
});

app.synth();
