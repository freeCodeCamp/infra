import yaml from 'js-yaml';
import { BASE64_ENCODED_CUSTOM_DATA } from '../env';

const testSource = (source: string, debugCloudInit: boolean): boolean => {
  // Test the cloud-init data Syntax
  try {
    const jsonCloudInit = yaml.load(source);
    if (debugCloudInit) {
      console.log(yaml.dump(jsonCloudInit));
    }
    return true;
  } catch (e) {
    throw new Error(`

      Error:
      Cloud-init data is not valid.

      ${e}
      `);
  }
};

export const getCloudInitData = () => {
  // Decode the intial base64 encoded cloud-init data
  const intialCloudInit = Buffer.from(
    BASE64_ENCODED_CUSTOM_DATA || '',
    'base64'
  ).toString('ascii');
  // Append more cloud-init data
  const source = `${intialCloudInit}`;
  // Change the value to true to debug the cloud-init data
  testSource(source, false);
  // Encode the cloud-init data to base64 from the 'source'
  return Buffer.from(source, 'utf8').toString('base64');
};
