import { Construct } from 'constructs';
import { PublicIp, ResourceGroup } from '@cdktf/provider-azurerm';

export const createPublicIp = (
  stack: Construct,
  name: string,
  rg: ResourceGroup,
  env: string
) => {
  return new PublicIp(stack, `${env}-public-ip-${name}`, {
    name: `${env}-public-ip-${name}`,
    resourceGroupName: rg.name,
    location: rg.location,
    allocationMethod: 'Static',
    sku: 'Basic'
  });
};
