import { resolve } from 'path';
import dotenv from 'dotenv';

const envPath = resolve(__dirname, '../.env');
const { error } = dotenv.config({ path: envPath });
if (error) {
  console.info(
    `
      Warning: .env file not found. You can ignore this
      message if you are using some other way of setting
      the required keys & secrets.
    `
  );
}

if (
  error &&
  (!process.env.DOPPLER_PROJECT || process.env.DOPPLER_PROJECT !== 'infra')
) {
  console.error(`Error: Doppler project is ${process.env.DOPPLER_PROJECT}`);
  throw error.message;
}

const {
  SSH_PUBLIC_KEY: sshPublicKey,
  GITHUB_PA_TOKEN: githubPAToken,
  BASE64_ENCODED_CUSTOM_DATA: customData,
  MYSQL_ADMIN_USERNAME: mysqlAdminUsername,
  MYSQL_ADMIN_PASSWORD: mysqlAdminPassword,
  MYSQL_FS_SKU: mysqlFsSku,
  MYSQL_FS_BACKUP_RETENTION_DAYS: mysqlFsBackupRetentionDays
} = process.env;

// TODO: Add valiadtion for all required env variables

export const ssh_public_key: string = String(sshPublicKey).toString();

export const github_pa_token: string = githubPAToken
  ? String(githubPAToken).toString()
  : '';

export const custom_data: string = String(customData).toString();

export const mysql_admin_username: string =
  String(mysqlAdminUsername).toString();

export const mysql_admin_password: string =
  String(mysqlAdminPassword).toString();

export const mysql_fs_sku: string = mysqlFsSku
  ? String(mysqlFsSku).toString()
  : 'B_Standard_B2s';

export const mysql_fs_backup_retention_days: number = mysqlFsBackupRetentionDays
  ? Number(mysqlFsBackupRetentionDays)
  : 7;
