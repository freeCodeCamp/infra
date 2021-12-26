import { Construct } from 'constructs';
import { App, RemoteBackend } from 'cdktf';

export const createRemoteBackend = (stack: Construct, stackName: string) => {
  return new RemoteBackend(stack, {
    hostname: 'app.terraform.io',
    organization: 'freecodecamp',
    workspaces: {
      name: `tfws-${stackName}`
    }
  });
};

interface StackConfig {
  stackConstruct: any;
  stackName: string;
}
export const createRemoteBackends = (app: App, config: StackConfig[]) => {
  config.forEach(({ stackConstruct, stackName }) => {
    const stack = new stackConstruct(app, stackName);
    createRemoteBackend(stack, stackName);
  });
};
