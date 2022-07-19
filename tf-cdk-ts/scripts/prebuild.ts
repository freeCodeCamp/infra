/**

    Dynamic code is not supported by CDKTF. You can't do promises,
    async / await, or fetch data from third-party APIs during the
    Synth process.

    https://github.com/hashicorp/terraform-cdk/issues/435


    This script is run ahead of time to get and store data as json files on local filesystem.

*/

import path from 'path';
import { writeFileSync, mkdirSync } from 'fs';
import { azure_subscription_id } from '../config/env';
import { getSSHKeysForUsersOnGitHubTeam } from './github';
import { listAllVirtualMachineImagesInASubscription } from './azure';

(() => {
  console.log(`

    Starting third-party API Calls. This will take a few minutes. You should run this only in PRODUCTION mode or in CI/CD.

  `);

  getSSHKeysForUsersOnGitHubTeam('freeCodeCamp', 'ops')
    .then(keys => {
      mkdirSync(path.join(__dirname, `/data`), { recursive: true });
      writeFileSync(
        path.join(__dirname, `/data/github-members.json`),
        JSON.stringify(keys)
      );
    })
    .catch(console.error);

  listAllVirtualMachineImagesInASubscription(azure_subscription_id)
    .then(list => {
      mkdirSync(path.join(__dirname, `/data`), { recursive: true });
      writeFileSync(
        path.join(__dirname, `/data/machine-images.json`),
        JSON.stringify(list)
      );
    })
    .catch(console.error);
})();
