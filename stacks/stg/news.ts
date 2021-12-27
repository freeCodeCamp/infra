import { Construct } from 'constructs';
import { TerraformStack } from 'cdktf';
import {
  AppService,
  AppServicePlan,
  AzurermProvider,
  ResourceGroup
} from '@cdktf/provider-azurerm';

// import { LinuxWebApp } from './../.gen/providers/azurerm/linux-web-app';

export default class NewsStack extends TerraformStack {
  constructor(scope: Construct, name: string, config: any) {
    super(scope, name);

    const { env } = config;

    new AzurermProvider(this, 'azurerm', {
      features: {}
    });

    const rgIdentifier = `${env}-rg-${name}`;
    const rg = new ResourceGroup(this, rgIdentifier, {
      name: rgIdentifier,
      location: 'eastus'
    });

    const appServicePlanIdentifier = `${env}-asp-${name}`;
    const appServicePlan = new AppServicePlan(this, appServicePlanIdentifier, {
      name: appServicePlanIdentifier,
      resourceGroupName: rg.name,
      location: rg.location,
      sku: {
        tier: 'PremiumV2',
        size: 'P1v2'
      }
    });

    const webAppIdentifier = `${env}-wa-${name}-test`;
    new AppService(this, webAppIdentifier, {
      name: webAppIdentifier,
      resourceGroupName: rg.name,
      location: rg.location,
      appServicePlanId: appServicePlan.id,
      siteConfig: {
        linuxFxVersion: 'DOCKER|ghcr.io/freecodecamp/landing-initial:latest',
        alwaysOn: true,
        ftpsState: 'Disabled',
        http2Enabled: true
      },
      authSettings: {
        enabled: false
      }
    });

    // const linuxWebAppIdentifier = `${env}-lwa-${name}-test`;
    // new LinuxWebApp(this, linuxWebAppIdentifier, {
    //   name: linuxWebAppIdentifier,
    //   resourceGroupName: rg.name,
    //   location: rg.location,
    //   servicePlanId: appServicePlan.id,
    //   authSettings: {
    //     enabled: false
    //   },
    //   siteConfig: {
    //     // linuxFxVersion: 'DOCKER|mcr.microsoft.com/appsvc/staticsite:latest',
    //     alwaysOn: true,
    //     ftpsState: 'Disabled',
    //     applicationStack: {
    //       dockerImage: 'ghcr.io/freecodecamp/landing-initial',
    //       dockerImageTag: 'latest'
    //     }
    //   }
    // });
  }
}
