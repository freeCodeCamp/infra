import { Construct } from 'constructs';
import { DnsARecord, PublicIp, ResourceGroup } from '@cdktf/provider-azurerm';

export const createPublicIp = (
  stack: Construct,
  {
    stackName,
    vmName,
    rg,
    env,
    createPublicDnsARecord = true
  }: {
    stackName: string;
    vmName: string;
    rg: ResourceGroup;
    env: string;
    createPublicDnsARecord?: boolean;
  }
) => {
  const pubIp = new PublicIp(stack, `${env}-ip-${stackName}-${vmName}`, {
    dependsOn: [rg],
    name: `${env}-ip-${stackName}-${vmName}`,
    resourceGroupName: rg.name,
    location: rg.location,
    allocationMethod: 'Static',
    sku: 'Standard',
    domainNameLabel: `${env}-${vmName}-${stackName}`
  });

  if (createPublicDnsARecord) {
    new DnsARecord(stack, `${env}-dns-a-record-${stackName}-${vmName}`, {
      dependsOn: [pubIp],
      name: `${vmName}.${stackName}`,
      resourceGroupName: 'ops-rg-common',
      zoneName:
        env === 'prd' ? 'pubdns.freecodecamp.org' : 'pubdns.freecodecamp.dev',
      ttl: 60,
      targetResourceId: pubIp.id
    });
  }

  return pubIp;
};
