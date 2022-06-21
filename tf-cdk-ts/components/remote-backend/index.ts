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

export interface StackConfigOptions {
  env: string;
  name: string;
  tlds?: string[];
}
export interface StackOptions {
  stackConstruct: any;
  stackConfig: StackConfigOptions;
}

export const createRemoteBackends = (app: App, config: StackOptions[]) => {
  config.forEach(({ stackConstruct, stackConfig }) => {
    const { env, name } = stackConfig;
    const stack = new stackConstruct(app, `${env}-${name}`, stackConfig);
    createRemoteBackend(stack, name, env);
  });
};
