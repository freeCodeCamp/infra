import { Octokit } from '@octokit/core';
import { github_pa_token } from '../config/env';

const octokit = new Octokit({
  auth: github_pa_token
});

interface keyMap {
  username: string;
  publicKeys: string[];
}

// Get members of a GitHub team
export const getMembersFromGHTeam = async (
  org: string,
  team_slug: string
): Promise<string[]> => {
  const data = await octokit
    .request(`GET /orgs/${org}/teams/${team_slug}/members`, {
      org,
      team_slug
    })
    .then(res => {
      return res.data;
    })
    .catch(err => {
      console.error(
        `
        Error getting team members for ${org}'s ${team_slug} team from GitHub.
        Check that you have configured the PA Token correctly and it has the
        correct scopes.

        Status: ${err.status}
        Message: ${err.message}
        `
      );
      return [];
    });

  return data.map(({ login: username }: { login: string }) => username);
};

// Get SSH public keys for 1 User from GitHub
export const getSSHKeysFor1User = async (user: string): Promise<keyMap> => {
  const data = await octokit
    .request(`GET /users/${user}/keys`, { username: user })
    .then(res => {
      return res.data;
    })
    .catch(err => {
      console.error(
        `Error getting public SSH keys for user ${user}. Got status: ${err.status}`
      );
      return { username: user, publicKeys: [] };
    });

  return {
    username: user,
    publicKeys: data.map(({ key }: { key: string }) => key)
  };
};

// Get SSH public keys for N (array) Users from GitHub
export const getSSHKeysForNUser = async (users: string[]) => {
  const keys = await Promise.all(users.map(getSSHKeysFor1User));
  return keys;
};

// Get SSH public keys for all users on a GitHub team
export const getSSHKeysForUsersOnGitHubTeam = async (
  org: string,
  team: string
) => {
  const members = await getMembersFromGHTeam(org, team);
  return await getSSHKeysForNUser(members);
};
