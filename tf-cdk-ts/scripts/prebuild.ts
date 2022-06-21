/**

    Dynamic code is not supported by CDKTF. You can't do promises, 
    async / await, or fetch data from third-party APIs during the 
    Synth process.

    https://github.com/hashicorp/terraform-cdk/issues/435


    This script is run ahead of time to get and store data as json files on local filesystem.

*/
import path = require('path');
import { writeFileSync, mkdirSync } from 'fs';
import { getSSHKeysForUsersOnGitHubTeam } from '../utils/github';

(() => {
  getSSHKeysForUsersOnGitHubTeam('freeCodeCamp', 'ops').then(keys => {
    mkdirSync(path.join(__dirname, `/data`), { recursive: true });
    writeFileSync(
      path.join(__dirname, `/data/github-members.json`),
      JSON.stringify(keys)
    );
  });
})();
