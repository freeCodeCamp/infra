import { Construct } from 'constructs';
import { App, RemoteBackend } from 'cdktf';

export const createRemoteBackend = (
  stack: Construct,
  stackName: string,
  env: string
) => {
  return new RemoteBackend(stack, {
    hostname: 'app.terraform.io',
    organization: 'freecodecamp',
    workspaces: {
      name: `tfws-${env}-stack-${stackName}`
    }
  });
};

interface StackConstructConfig {
  stackConstruct: any;
  stackName: string;
  stackConfig: any;
}
export const createRemoteBackends = (
  app: App,
  config: StackConstructConfig[]
) => {
  config.forEach(({ stackConstruct, stackName, stackConfig }) => {
    const stack = new stackConstruct(app, stackName, stackConfig);
    const { env } = stackConfig;
    createRemoteBackend(stack, stackName, env);
  });
};
