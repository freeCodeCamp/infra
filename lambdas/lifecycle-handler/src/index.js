import {
  ASClient,
  CompleteLifecycleActionCommand
} from '@aws-sdk/client-auto-scaling';
import { EC2Client, DescribeInstancesCommand } from '@aws-sdk/client-ec2';

const NOMAD_ADDR = process.env.NOMAD_ADDR || '';

export const handler = async (event) => {
  console.log('Received event:', JSON.stringify(event, null, 2));

  const asgClient = new ASClient({});
  const ec2Client = new EC2Client({});

  const {
    EC2InstanceId: instanceId,
    AutoScalingGroupName: asgName,
    LifecycleHookName: lifecycleHookName
  } = event.detail;

  try {
    // Get EC2 instance details
    const describeInstancesCommand = new DescribeInstancesCommand({
      InstanceIds: [instanceId]
    });
    const { Reservations } = await ec2Client.send(describeInstancesCommand);
    const instance = Reservations?.[0]?.Instances?.[0];

    if (!instance) {
      throw new Error(`Instance ${instanceId} not found`);
    }

    const { PrivateIpAddress: privateIp, Tags } = instance;
    const tags = Object.fromEntries(
      Tags?.map(({ Key, Value }) => [Key, Value]) || []
    );

    const nomadDatacenter = tags['NomadDatacenter'] || 'default';
    const nomadNodePool = tags['NomadNodePool'] || 'default';

    console.log(
      `Processing instance ${instanceId} (${privateIp}) in datacenter ${nomadDatacenter}, node pool ${nomadNodePool}`
    );

    // Find corresponding Nomad node
    const nodesResponse = await fetch(`${NOMAD_ADDR}/v1/nodes`);
    if (!nodesResponse.ok) {
      throw new Error(
        `Failed to fetch Nomad nodes: ${nodesResponse.statusText}`
      );
    }
    const nodes = await nodesResponse.json();
    const node = nodes.find(
      (node) =>
        node.Address === privateIp &&
        node.Datacenter === nomadDatacenter &&
        node.NodePool === nomadNodePool
    );

    if (node) {
      console.log(`Found Nomad node ${node.ID}`);
      // Initiate node drain
      const drainResponse = await fetch(
        `${NOMAD_ADDR}/v1/node/${node.ID}/drain`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            Enable: true,
            Deadline: '5m'
          })
        }
      );
      if (!drainResponse.ok) {
        throw new Error(
          `Failed to start node drain: ${drainResponse.statusText}`
        );
      }

      console.log(`Started draining node ${node.ID}`);

      // Monitor drain status
      const maxRetries = 30; // 5 minutes (30 * 10 seconds)
      let retries = 0;
      while (retries < maxRetries) {
        const statusResponse = await fetch(`${NOMAD_ADDR}/v1/node/${node.ID}`);
        if (!statusResponse.ok) {
          throw new Error(
            `Failed to fetch node status: ${statusResponse.statusText}`
          );
        }
        const nodeStatus = await statusResponse.json();
        if (!nodeStatus.DrainStrategy) {
          console.log(`Node ${node.ID} drain complete`);
          break;
        }
        retries++;
        await new Promise((resolve) => setTimeout(resolve, 10000)); // Wait for 10 seconds
      }
      if (retries >= maxRetries) {
        console.warn(
          `Node ${node.ID} drain did not complete within the expected time`
        );
      }
    } else {
      console.log(`No matching Nomad node found for instance ${instanceId}`);
    }

    // Complete lifecycle action
    const completeLifecycleActionCommand = new CompleteLifecycleActionCommand({
      LifecycleHookName: lifecycleHookName,
      AutoScalingGroupName: asgName,
      InstanceId: instanceId,
      LifecycleActionResult: 'CONTINUE'
    });

    await asgClient.send(completeLifecycleActionCommand);
    console.log(`Completed lifecycle action for instance ${instanceId}`);
  } catch (error) {
    console.error('Error:', error);
    try {
      // Abandon lifecycle action on error
      const completeLifecycleActionCommand = new CompleteLifecycleActionCommand(
        {
          LifecycleHookName: lifecycleHookName,
          AutoScalingGroupName: asgName,
          InstanceId: instanceId,
          LifecycleActionResult: 'ABANDON'
        }
      );
      await asgClient.send(completeLifecycleActionCommand);
      console.log(
        `Abandoned lifecycle action for instance ${instanceId} due to error`
      );
    } catch (completeError) {
      console.error('Error completing lifecycle action:', completeError);
    }
    throw error;
  }
};
