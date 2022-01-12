import { Construct } from 'constructs';
import {
  MysqlFlexibleServer,
  MysqlFlexibleServerConfig
} from '@cdktf/provider-azurerm';

import { mysql_admin_username, mysql_admin_password } from '../../config/env';

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
      Burstable (B)         : "Standard_B1ms"     --> "B_Standard_B1ms"
      
      ...and so on.
    */
    skuName: config.skuName || 'B_Standard_B1ms',

    storage: {
      autoGrowEnabled: config.storage?.autoGrowEnabled || true,
      iops: config.storage?.iops || 400,
      sizeGb: config.storage?.sizeGb || 20
    },
    version: '5.7',
    administratorLogin: mysql_admin_username,
    administratorPassword: mysql_admin_password,

    // Backup and Availability settings
    // highAvailability: {                         // Do not use High Availability - because Ghost doesn't support it
    //   mode: 'ZoneRedundant'                     // High Availability is not available on all SKUs
    // },
    backupRetentionDays: 7,
    geoRedundantBackupEnabled: true,

    // Network settings
    delegatedSubnetId: config.delegatedSubnetId
    // privateDnsZoneId: config.privateDnsZoneId
  });
};
