import { resolve } from 'path';
import dotenv from 'dotenv';

const envPath = resolve(__dirname, '../.env');
const { error } = dotenv.config({ path: envPath });
if (error) {
  console.info(`

    Warning:
    .env file not found. You can ignore this message if you are using
    some other way of setting the required keys & secrets.

  `);
}

if (
  error &&
  (!process.env.DOPPLER_PROJECT || process.env.DOPPLER_PROJECT !== 'infra')
) {
  throw new Error(`

    Error:
    Doppler project is ${process.env.DOPPLER_PROJECT}

  `);
}

const {
  AZURE_SUBSCRIPTION_ID: azureSubscriptionId,
  SSH_PUBLIC_KEY: sshPublicKey,
  // GitHub Personal Access Token,
  // from a member belonging to the GitHub team,
  // whose public keys need to be imported.
  PA_TOKEN_FROM_GITHUB: githubPAToken,
  BASE64_ENCODED_CUSTOM_DATA: customData,
  MYSQL_ADMIN_USERNAME: mysqlAdminUsername,
  MYSQL_ADMIN_PASSWORD: mysqlAdminPassword,
  MYSQL_FS_SKU: mysqlFsSku,
  MYSQL_FS_BACKUP_RETENTION_DAYS: mysqlFsBackupRetentionDays
} = process.env;

// TODO: Add valiadtion for all required env variables

export const PA_TOKEN_FROM_GITHUB: string = githubPAToken
  ? String(githubPAToken).toString()
  : '';

export const AZURE_SUBSCRIPTION_ID: string =
  String(azureSubscriptionId).toString();

export const SSH_PUBLIC_KEY: string = String(sshPublicKey).toString();
export const BASE64_ENCODED_CUSTOM_DATA: string = String(customData).toString();

export const MYSQL_ADMIN_USERNAME: string =
  String(mysqlAdminUsername).toString();
export const MYSQL_ADMIN_PASSWORD: string =
  String(mysqlAdminPassword).toString();

export const MYSQL_FS_SKU: string = mysqlFsSku
  ? String(mysqlFsSku).toString()
  : 'B_Standard_B2s';
export const MYSQL_FS_BACKUP_RETENTION_DAYS: number = mysqlFsBackupRetentionDays
  ? Number(mysqlFsBackupRetentionDays)
  : 7;
