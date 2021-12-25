import { Construct } from 'constructs';
import {
  MysqlFlexibleServer,
  MysqlFlexibleServerConfig
} from '@cdktf/provider-azurerm';

import {
  mysql_fs_sku,
  mysql_admin_username,
  mysql_admin_password,
  mysql_fs_backup_retention_days
} from '../../../config/env';

export default class fCCMysqlFlexibleServer extends MysqlFlexibleServer {
  constructor(
    scope: Construct,
    name: string,
    config: MysqlFlexibleServerConfig
  ) {
    super(scope, name, config);

    new MysqlFlexibleServer(this, 'prd-fs-mysql-db', {
      name: 'prd-fs-mysql-db',

      resourceGroupName: config.resourceGroupName,
      location: config.location,

      skuName: mysql_fs_sku,

      administratorLogin: mysql_admin_username,
      administratorPassword: mysql_admin_password,

      backupRetentionDays: mysql_fs_backup_retention_days,

      // highAvailability: {
      //   mode: 'SameZone'
      // },

      storage: {
        autoGrowEnabled: true,
        iops: 400,
        sizeGb: 20
      },

      version: '5.7',

      delegatedSubnetId: config.delegatedSubnetId
    });
  }
}
