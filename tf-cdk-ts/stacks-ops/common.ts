import { Construct } from 'constructs';
import { TerraformStack } from 'cdktf';
import {
  AzurermProvider,
  DnsZone,
  PrivateDnsZone,
  ResourceGroup,
  SshPublicKey
} from '@cdktf/provider-azurerm';

import { createAzureRBACServicePrincipal } from '../config/service_principal';
import { StackConfigOptions } from '../components/remote-backend/index';
import { importSSHPublicKeyMembers } from '../utils';

export default class CommonStack extends TerraformStack {
  constructor(
    scope: Construct,
    tfConstructName: string,
    config: StackConfigOptions
  ) {
    super(scope, tfConstructName);

    const { env, name, tlds } = config;

    const { subscriptionId, tenantId, clientId, clientSecret } =
      createAzureRBACServicePrincipal(this);

    new AzurermProvider(this, 'azurerm', {
      features: {},
      subscriptionId: subscriptionId.stringValue,
      tenantId: tenantId.stringValue,
      clientId: clientId.stringValue,
      clientSecret: clientSecret.stringValue
    });

    const rgIdentifier = `${env}-rg-${name}`;
    const rg = new ResourceGroup(this, rgIdentifier, {
      name: rgIdentifier,
      location: 'eastus'
    });

    // Create SSH keys for all members of the ops team
    importSSHPublicKeyMembers().forEach(
      (member: { username: string; publicKeys: string[] }) => {
        // console.log(`Creating SSH keys for ${member?.username}`);
        member?.publicKeys.forEach((key, index) => {
          // console.log(
          //   `Key ${index + 1}: ${key.slice(0, 20)}...${key.slice(-20)}`
          // );
          const sshPublicKeyIdentifier = `${env}-ssh-key-${member.username}-${
            index + 1
          }`;
          new SshPublicKey(this, sshPublicKeyIdentifier, {
            dependsOn: [rg],
            name: sshPublicKeyIdentifier,
            resourceGroupName: rg.name,
            location: rg.location,
            publicKey: key
          });
        });
      }
    );

    // Create Private DNS Zones for each domain
    tlds?.forEach((tld: string) => {
      new PrivateDnsZone(this, `${env}-prvdns-${tld}`, {
        name: `prvdns.freecodecamp.${tld}`,
        resourceGroupName: rg.name
      });
    });

    // Create Public DNS Zones for each domain
    tlds?.forEach((tld: string) => {
      new DnsZone(this, `${env}-pubdns-${tld}`, {
        name: `pubdns.freecodecamp.${tld}`,
        resourceGroupName: rg.name
      });
    });
  }
}
