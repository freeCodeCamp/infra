import { config } from 'dotenv';
import { resolve } from 'path';
import { existsSync } from 'fs';

const envPath = resolve(__dirname, '../.env');

if (!existsSync(envPath)) {
  throw Error(`Could not locate environment variables file.`);
}
config({ path: envPath });

const {
  SSH_PUBLIC_KEY: sshPublicKey,
  BASE64_ENCODED_CUSTOM_DATA: customData
} = process.env;

export const ssh_public_key: string = String(sshPublicKey).toString();
export const custom_data: string = String(customData).toString();
