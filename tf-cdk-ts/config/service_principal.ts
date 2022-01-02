import { Construct } from 'constructs';
import { TerraformVariable } from 'cdktf';

export const createAzureRBACServicePrincipal = (scope: Construct) => {
  return {
    subscriptionId: new TerraformVariable(scope, 'subscription_id', {
      type: 'string',
      default: '',
      description: 'The Azure subscription ID.'
    }),
    tenantId: new TerraformVariable(scope, 'tenant_id', {
      type: 'string',
      default: '',
      description: 'The Azure tenant ID.'
    }),
    clientId: new TerraformVariable(scope, 'client_id', {
      type: 'string',
      default: '',
      description: 'The Azure application ID.'
    }),
    clientSecret: new TerraformVariable(scope, 'client_secret', {
      type: 'string',
      default: '',
      description: 'The Azure application password.',
      sensitive: true
    })
  };
};
