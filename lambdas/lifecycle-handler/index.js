const {
  AutoScalingClient,
  CompleteLifecycleActionCommand,
  RecordLifecycleActionHeartbeatCommand
} = require('@aws-sdk/client-auto-scaling');
const { EC2Client, DescribeInstancesCommand } = require('@aws-sdk/client-ec2');
const {
  SSMClient,
  SendCommandCommand,
  GetCommandInvocationCommand
} = require('@aws-sdk/client-ssm');

const NOMAD_ADDR = process.env.NOMAD_ADDR || '';
const LAMBDA_TIMEOUT = 290; // Set this to 10 seconds less than the ASG lifecycle hook timeout

exports.handler = async (event) => {
  console.log('Received event:', JSON.stringify(event, null, 2));

  const asgClient = new AutoScalingClient({});
  const ec2Client = new EC2Client({});
  const ssmClient = new SSMClient({});

  const {
    EC2InstanceId: instanceId,
    AutoScalingGroupName: asgName,
    LifecycleHookName: lifecycleHookName
  } = event.detail;

  const startTime = Date.now();

  try {
    // Fetch EC2 instance details
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

    // Prepare SSM command to drain Nomad node
    const ssmCommand = `
      #!/bin/bash
      set -e
      export NOMAD_ADDR="${NOMAD_ADDR}"

      # Get the Nomad node ID
      NODE_ID=$(nomad node status -self -t '{{ .ID }}')

      if [ -z "$NODE_ID" ]; then
        echo "ERROR: No Nomad node found on this instance"
        exit 1
      fi

      echo "INFO: Found Nomad node $NODE_ID"

      # Start draining the node
      nomad node drain -enable -deadline 5m "$NODE_ID"

      # Wait for drain to complete
      for i in {1..30}; do
        if ! nomad node status "$NODE_ID" | grep -q 'Draining: true'; then
          echo "INFO: Node $NODE_ID drain complete"
          exit 0
        fi
        echo "INFO: Drain in progress, waiting..."
        sleep 10
      done

      echo "WARNING: Node $NODE_ID drain did not complete within the expected time"
      exit 2
    `;

    // Send SSM command to drain Nomad node
    const sendCommandCommand = new SendCommandCommand({
      InstanceIds: [instanceId],
      DocumentName: 'AWS-RunShellScript',
      Parameters: {
        commands: [ssmCommand]
      }
    });

    const commandResult = await ssmClient.send(sendCommandCommand);
    console.log('SSM Command sent:', commandResult.Command.CommandId);

    // Wait for SSM command completion with heartbeat extension
    let commandStatus = 'InProgress';
    while (commandStatus === 'InProgress') {
      if (Date.now() - startTime > LAMBDA_TIMEOUT * 1000) {
        throw new Error('Lambda execution time limit reached');
      }

      await new Promise((resolve) => setTimeout(resolve, 10000)); // Wait for 10 seconds

      const getCommandInvocation = new GetCommandInvocationCommand({
        CommandId: commandResult.Command.CommandId,
        InstanceId: instanceId
      });
      const invocationResult = await ssmClient.send(getCommandInvocation);
      commandStatus = invocationResult.Status;

      console.log(`Command status: ${commandStatus}`);

      // Analyze command output
      if (invocationResult.StandardOutputContent) {
        const outputLines = invocationResult.StandardOutputContent.split('\n');
        for (const line of outputLines) {
          if (line.startsWith('ERROR:')) {
            throw new Error(`SSM command error: ${line}`);
          } else if (line.startsWith('WARNING:')) {
            console.warn(`SSM command warning: ${line}`);
          } else if (line.startsWith('INFO:')) {
            console.log(`SSM command info: ${line}`);
          }
        }
      }

      // Extend lifecycle hook if necessary
      if (Date.now() - startTime > 240000) {
        // 4 minutes
        const recordHeartbeatCommand =
          new RecordLifecycleActionHeartbeatCommand({
            LifecycleHookName: lifecycleHookName,
            AutoScalingGroupName: asgName,
            InstanceId: instanceId
          });
        await asgClient.send(recordHeartbeatCommand);
        console.log('Lifecycle hook heartbeat recorded');
      }
    }

    if (commandStatus !== 'Success') {
      throw new Error(`SSM command failed with status: ${commandStatus}`);
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
