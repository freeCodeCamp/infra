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

const LAMBDA_TIMEOUT = 290; // 10 seconds less than the ASG lifecycle hook timeout

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

    if (!instance || instance.State.Name !== 'running') {
      console.log(
        `Instance ${instanceId} not found or not running. Skipping drain process.`
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
      `Processing instance ${instanceId} (${instance.PrivateIpAddress})`
    );

    const ssmCommand = buildSSMCommand();
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
  const { Reservations } = await ec2Client.send(
    new DescribeInstancesCommand({ InstanceIds: [instanceId] })
  );
  return Reservations?.[0]?.Instances?.[0];
}

function buildSSMCommand() {
  return `
    #!/bin/bash
    set -e

    sudo -u freecodecamp bash << 'EOF'
    set -e

    echo "INFO: Starting Nomad drain process"

    if ! command -v nomad &> /dev/null; then
        echo "ERROR: nomad command not found. PATH is: $PATH"
        exit 1
    fi

    echo "INFO: Found nomad at $(which nomad)"
    echo "INFO: Checking Nomad agent status"
    sudo systemctl status nomad || true

    echo "INFO: Last 20 lines of Nomad agent logs:"
    sudo journalctl -u nomad -n 20 || true

    echo "INFO: Attempting to list Nomad nodes"
    nomad node status || echo "Failed to list Nomad nodes"

    NODE_ID=$(nomad node status -self -t '{{ .ID }}')

    if [ -z "$NODE_ID" ]; then
      echo "ERROR: Could not determine Nomad node ID for this instance"
      exit 1
    fi

    echo "INFO: Found Nomad node $NODE_ID"
    echo "INFO: Starting drain process for node $NODE_ID"
    nomad node drain -enable -deadline 5m "$NODE_ID"

    for i in {1..30}; do
      if ! nomad node status "$NODE_ID" | grep -q 'Drain: true'; then
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
  try {
    const commandResult = await ssmClient.send(
      new SendCommandCommand({
        InstanceIds: [instanceId],
        DocumentName: 'AWS-RunShellScript',
        Parameters: { commands: [command] }
      })
    );
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
    if (Date.now() - startTime > LAMBDA_TIMEOUT * 1000) {
      console.warn(
        'Lambda execution time limit reached, but drain may still be in progress'
      );
      break;
    }

    await new Promise((resolve) => setTimeout(resolve, 10000));

    try {
      const invocationResult = await ssmClient.send(
        new GetCommandInvocationCommand({
          CommandId: commandId,
          InstanceId: instanceId
        })
      );
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

      if (
        commandStatus === 'Failed' ||
        invocationResult.StandardErrorContent.includes('ERROR:')
      ) {
        console.error(
          'SSM command failed or encountered an error. Check the logs above for details.'
        );
        return;
      }
    } catch (invocationError) {
      console.error('Failed to get command invocation:', invocationError);
    }

    if (Date.now() - lastHeartbeatTime > 240000) {
      await recordLifecycleActionHeartbeat(
        asgName,
        instanceId,
        lifecycleHookName,
        lifecycleActionToken
      );
      lastHeartbeatTime = Date.now();
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
    await asgClient.send(
      new CompleteLifecycleActionCommand({
        LifecycleHookName: lifecycleHookName,
        AutoScalingGroupName: asgName,
        InstanceId: instanceId,
        LifecycleActionToken: lifecycleActionToken,
        LifecycleActionResult: result
      })
    );
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
    await asgClient.send(
      new RecordLifecycleActionHeartbeatCommand({
        LifecycleHookName: lifecycleHookName,
        AutoScalingGroupName: asgName,
        InstanceId: instanceId,
        LifecycleActionToken: lifecycleActionToken
      })
    );
    console.log('Lifecycle hook heartbeat recorded');
  } catch (error) {
    console.warn('Failed to record lifecycle heartbeat:', error);
  }
}
