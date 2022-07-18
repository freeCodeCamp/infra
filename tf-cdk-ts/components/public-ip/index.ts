import { Construct } from 'constructs';
import { DnsARecord, PublicIp, ResourceGroup } from '@cdktf/provider-azurerm';

export const createPublicIp = (
  stack: Construct,
  name: string,
  rg: ResourceGroup,
  env: string
) => {
  const pubIp = new PublicIp(stack, `${env}-public-ip-${name}`, {
    name: `${env}-public-ip-${name}`,
    resourceGroupName: rg.name,
    location: rg.location,
    allocationMethod: 'Static',
    sku: 'Standard'
  });

  new DnsARecord(stack, `${env}-dns-a-record-${name}`, {
    name: String(`${env}${name}`).replaceAll('-', ''),
    resourceGroupName: 'ops-rg-common',
    zoneName:
      env === 'prd' ? 'pubdns.freecodecamp.org' : 'pubdns.freecodecamp.dev',
    ttl: 60,
    targetResourceId: pubIp.id
  });

  return pubIp;
};
