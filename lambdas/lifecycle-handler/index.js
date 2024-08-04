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

const asgClient = new AutoScalingClient({});
const ec2Client = new EC2Client({});
const ssmClient = new SSMClient({});

exports.handler = async (event) => {
  console.log('Received event:', JSON.stringify(event, null, 2));

  const {
    LifecycleActionToken: lifecycleActionToken,
    AutoScalingGroupName: asgName,
    LifecycleHookName: lifecycleHookName,
    EC2InstanceId: instanceId
  } = event.detail;

  const startTime = Date.now();

  try {
    const instance = await getEC2InstanceDetails(instanceId);

    if (!instance) {
      console.log(
        `Instance ${instanceId} not found. It may have been terminated.`
      );
      await completeLifecycleAction(
        asgName,
        instanceId,
        lifecycleHookName,
        lifecycleActionToken,
        'CONTINUE'
      );
      return;
    }

    const { privateIp, instanceState, nomadDatacenter, nomadNodePool } =
      extractInstanceInfo(instance);

    console.log(`Instance ${instanceId} state: ${instanceState}`);

    if (instanceState !== 'running') {
      console.log(
        `Instance ${instanceId} is not in running state. Skipping drain process.`
      );
      await completeLifecycleAction(
        asgName,
        instanceId,
        lifecycleHookName,
        lifecycleActionToken,
        'CONTINUE'
      );
      return;
    }

    console.log(
      `Processing instance ${instanceId} (${privateIp}) in datacenter ${nomadDatacenter}, node pool ${nomadNodePool}`
    );

    const ssmCommand = buildSSMCommand(NOMAD_ADDR);
    const commandResult = await sendSSMCommand(instanceId, ssmCommand);

    await waitForCommandCompletion(
      commandResult.Command.CommandId,
      instanceId,
      startTime,
      asgName,
      lifecycleHookName,
      lifecycleActionToken
    );

    await completeLifecycleAction(
      asgName,
      instanceId,
      lifecycleHookName,
      lifecycleActionToken,
      'CONTINUE'
    );
  } catch (error) {
    console.error('Error:', error);
    await completeLifecycleAction(
      asgName,
      instanceId,
      lifecycleHookName,
      lifecycleActionToken,
      'ABANDON'
    );
  }
};

async function getEC2InstanceDetails(instanceId) {
  const describeInstancesCommand = new DescribeInstancesCommand({
    InstanceIds: [instanceId]
  });
  const { Reservations } = await ec2Client.send(describeInstancesCommand);
  return Reservations?.[0]?.Instances?.[0];
}

function extractInstanceInfo(instance) {
  const {
    PrivateIpAddress: privateIp,
    State: { Name: instanceState },
    Tags
  } = instance;

  const tags = Tags.reduce((acc, tag) => {
    acc[tag.Key] = tag.Value;
    return acc;
  }, {});

  const nomadDatacenter = tags['NomadDatacenter'] || 'default';
  const nomadNodePool = tags['NomadNodePool'] || 'default';

  if (!tags['NomadDatacenter'] || !tags['NomadNodePool']) {
    console.warn(
      `Warning: Using default values for missing tags on instance ${instance.InstanceId}. NomadDatacenter: ${nomadDatacenter}, NomadNodePool: ${nomadNodePool}`
    );
  }

  return { privateIp, instanceState, nomadDatacenter, nomadNodePool };
}

function buildSSMCommand(nomadAddr) {
  return `
    #!/bin/bash
    set -e

    # Run the entire script as the freecodecamp user
    sudo -u freecodecamp bash << 'EOF'
    set -e

    export NOMAD_ADDR="${nomadAddr}"

    # Check if nomad command is available
    if ! command -v nomad &> /dev/null; then
        echo "ERROR: nomad command not found. PATH is: $PATH"
        exit 1
    fi

    echo "INFO: Found nomad at $(which nomad)"

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
    EOF
  `;
}

async function sendSSMCommand(instanceId, command) {
  const sendCommandCommand = new SendCommandCommand({
    InstanceIds: [instanceId],
    DocumentName: 'AWS-RunShellScript',
    Parameters: {
      commands: [command]
    }
  });

  try {
    const commandResult = await ssmClient.send(sendCommandCommand);
    console.log('SSM Command sent:', commandResult.Command.CommandId);
    return commandResult;
  } catch (ssmError) {
    console.error('Failed to send SSM command:', ssmError);
    throw ssmError;
  }
}

async function waitForCommandCompletion(
  commandId,
  instanceId,
  startTime,
  asgName,
  lifecycleHookName,
  lifecycleActionToken
) {
  let commandStatus = 'InProgress';
  let lastHeartbeatTime = startTime;

  while (commandStatus === 'InProgress') {
    const currentTime = Date.now();

    if (currentTime - startTime > LAMBDA_TIMEOUT * 1000) {
      console.warn(
        'Lambda execution time limit reached, but drain may still be in progress'
      );
      break;
    }

    await new Promise((resolve) => setTimeout(resolve, 10000)); // Wait for 10 seconds

    try {
      const getCommandInvocation = new GetCommandInvocationCommand({
        CommandId: commandId,
        InstanceId: instanceId
      });
      const invocationResult = await ssmClient.send(getCommandInvocation);
      commandStatus = invocationResult.Status;

      console.log(`Command status: ${commandStatus}`);

      if (invocationResult.StandardOutputContent) {
        console.log('Command output:', invocationResult.StandardOutputContent);
      }

      if (invocationResult.StandardErrorContent) {
        console.error(
          'Command error output:',
          invocationResult.StandardErrorContent
        );
      }
    } catch (invocationError) {
      console.error('Failed to get command invocation:', invocationError);
      // Continue the loop, as the command might still be running
    }

    // Extend lifecycle hook if necessary
    if (currentTime - lastHeartbeatTime > 240000) {
      // 4 minutes
      await recordLifecycleActionHeartbeat(
        asgName,
        instanceId,
        lifecycleHookName,
        lifecycleActionToken
      );
      lastHeartbeatTime = currentTime;
    }
  }

  if (commandStatus !== 'Success') {
    console.warn(
      `SSM command did not complete successfully. Final status: ${commandStatus}`
    );
  }
}

async function completeLifecycleAction(
  asgName,
  instanceId,
  lifecycleHookName,
  lifecycleActionToken,
  result
) {
  try {
    const completeLifecycleActionCommand = new CompleteLifecycleActionCommand({
      LifecycleHookName: lifecycleHookName,
      AutoScalingGroupName: asgName,
      InstanceId: instanceId,
      LifecycleActionToken: lifecycleActionToken,
      LifecycleActionResult: result
    });

    await asgClient.send(completeLifecycleActionCommand);
    console.log(
      `Completed lifecycle action for instance ${instanceId} with result: ${result}`
    );
  } catch (error) {
    console.warn(
      `Failed to complete lifecycle action for instance ${instanceId}:`,
      error
    );
  }
}

async function recordLifecycleActionHeartbeat(
  asgName,
  instanceId,
  lifecycleHookName,
  lifecycleActionToken
) {
  try {
    const recordHeartbeatCommand = new RecordLifecycleActionHeartbeatCommand({
      LifecycleHookName: lifecycleHookName,
      AutoScalingGroupName: asgName,
      InstanceId: instanceId,
      LifecycleActionToken: lifecycleActionToken
    });
    await asgClient.send(recordHeartbeatCommand);
    console.log('Lifecycle hook heartbeat recorded');
  } catch (error) {
    console.warn('Failed to record lifecycle heartbeat:', error);
  }
}
