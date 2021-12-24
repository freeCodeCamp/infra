import { resolve } from 'path';

const envPath = resolve(__dirname, '../.env');
const { error } = require('dotenv').config({ path: envPath });
if (error) {
  console.warn(`
  ----------------------------------------------------
  Warning: .env file not found.
  ----------------------------------------------------
  Please copy sample.env to .env
  You can ignore this warning if using a different way
  to setup this environment.
  ----------------------------------------------------
  `);
}

const { SSH_PUBLIC_KEY: sshPublicKey, BASE64_ENCODED_CUSTOM_DATA: customData } =
  process.env;

export const ssh_public_key: string = String(sshPublicKey).toString();
export const custom_data: string = String(customData).toString();
