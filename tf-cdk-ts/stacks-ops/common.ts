import { Construct } from 'constructs';
import { TerraformStack } from 'cdktf';
import { AzurermProvider } from '@cdktf/provider-azurerm/lib/provider';
import { ResourceGroup } from '@cdktf/provider-azurerm/lib/resource-group';
import { DnsZone } from '@cdktf/provider-azurerm/lib/dns-zone';
import { SshPublicKey } from '@cdktf/provider-azurerm/lib/ssh-public-key';

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

          const isRSAKey = key.startsWith('ssh-rsa');
          isRSAKey
            ? new SshPublicKey(this, sshPublicKeyIdentifier, {
                dependsOn: [rg],
                name: sshPublicKeyIdentifier,
                resourceGroupName: rg.name,
                location: rg.location,
                publicKey: key
              })
            : console.error(`

    Warning:
    Skipping SSH key ${key.slice(0, 20)}...${key.slice(-20)} from the user "${
                member.username
              }" because it is not a RSA-based key.
    Only RSA-based keys are supported by Azure.

          `);
        });
      }
    );

    // Create Public DNS Zones for each domain
    tlds?.forEach((tld: string) => {
      new DnsZone(this, `${env}-pubdns-${tld}`, {
        name: `pubdns.freecodecamp.${tld}`,
        resourceGroupName: rg.name
      });
    });
  }
}
