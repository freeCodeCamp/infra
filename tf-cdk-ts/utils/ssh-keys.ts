import { Octokit } from '@octokit/core';
import { github_pa_token } from '../config/env';

const octokit = new Octokit({
  auth: github_pa_token
});

interface keyMap {
  username: string;
  publicKeys: string[];
}

export const getSSHKeysForUser = async (user: string): Promise<keyMap> => {
  const data = await octokit
    .request(`GET /users/${user}/keys`, { username: user })
    .then((res) => {
      return res.data;
    })
    .catch((err) => {
      console.log(
        `Error getting public SSH keys for user ${user}. Got status: ${err.status}`
      );
      return [];
    });

  return Promise.resolve({
    username: user,
    publicKeys: data.map(({ key }: { key: string }) => key)
  });
};

export const getSSHKeys = async (users: string[]) => {
  return await Promise.all(users.map(getSSHKeysForUser));
};

// (async () => {
//   console.log(await getSSHKeysForUser('camperbot'));
//   console.log(await getSSHKeys(['raisedadead', 'camperbot']));
// })();
