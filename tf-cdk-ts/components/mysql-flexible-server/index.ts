import { Construct } from 'constructs';
import {
  MysqlFlexibleServer,
  MysqlFlexibleServerConfig
} from '@cdktf/provider-azurerm';

import { MYSQL_ADMIN_USERNAME, MYSQL_ADMIN_PASSWORD } from '../../config/env';

export const createMysqlFlexibleServer = (
  scope: Construct,
  name: string,
  config: MysqlFlexibleServerConfig
) => {
  return new MysqlFlexibleServer(scope, name, {
    // Basic settings
    name: String(config.name).replaceAll('-', ''), // Name needs to be unique accross regions and cannot have special characters
    resourceGroupName: config.resourceGroupName,
    location: config.location,

    /*
      !! Important !!

      Azure makes it horibily difficult to find the documentation about skuName (sku_name in HCL).

      You can get a list of SKUs with the following command:

      az mysql flexible-server list-skus -l eastus --query "[].supportedFlexibleServerEditions[].{Name:name, SKU:supportedServerVersions[].supportedSkus[].name}"

      The correct skuName format then is:

      General Purpose (GP)  : "Standard_D2ds_v4"  --> "GP_Standard_D2ds_v4"
      Burstable (B)         : "Standard_B2s"      --> "B_Standard_B2s"

      ...and so on.
    */
    skuName: config.skuName || 'B_Standard_B2s',

    storage: {
      autoGrowEnabled: config.storage?.autoGrowEnabled || true,
      iops: config.storage?.iops || 360,
      sizeGb: config.storage?.sizeGb || 20
    },
    version: '5.7',
    administratorLogin: MYSQL_ADMIN_USERNAME,
    administratorPassword: MYSQL_ADMIN_PASSWORD,

    backupRetentionDays: 7
  });
};
