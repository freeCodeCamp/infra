import { ComputeManagementClient } from '@azure/arm-compute';
import { DefaultAzureCredential } from '@azure/identity';

export const listAllVirtualMachineImagesInASubscription = async (
  subscriptionId: string
) => {
  if (!subscriptionId || subscriptionId.length === 0) {
    throw new Error(`

    Error:
    AZURE_SUBSCRIPTION_ID is not set. This is required for fetching the list of virtual machine images.

    `);
  }
  const credential = new DefaultAzureCredential();
  const client = new ComputeManagementClient(credential, subscriptionId);
  const resArray = [];
  for await (const item of client.images.list()) {
    resArray.push(item);
  }
  return resArray;
};
