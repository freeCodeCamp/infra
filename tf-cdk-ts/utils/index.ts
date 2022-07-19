import { customAlphabet } from 'nanoid';
import images from '../scripts/data/machine-images.json';

//
// Working with random IDs
//
const alphabet =
  '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
const nanoid = customAlphabet(alphabet, 5);
export const generateNanoid = (): string => nanoid();

//
// Working with Machine Images
//
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const groupBy = (list: Array<any>, key: string) => {
  return list.reduce((prev, current) => {
    (prev[current[key]] = prev[current[key]] || []).push(current);
    return prev;
  }, {});
};
export const getMachineImages = (imageType = '') => {
  const availableImages = images.map(({ id, name, location, tags }) => ({
    id,
    name,
    location,
    imageType: tags['ops-image-type']
  }));

  return imageType !== ''
    ? groupBy(availableImages, 'imageType')[imageType]
    : groupBy(availableImages, 'imageType');
};

interface MachineImage {
  id: string;
  name: string;
  location: string;
  imageType: string;
}
export const getLatestImage = (imageType: string, location: string) => {
  const requestedImageList: [MachineImage] = getMachineImages(imageType);
  const filteredImageList = requestedImageList.filter(
    (image: MachineImage) => image.location === location
  );
  const latestImage = filteredImageList.sort(
    // localeCompare returns -1, 0, 1 if a is 'before' b, t
    (a: MachineImage, b: MachineImage) => -1 * a.name.localeCompare(b.name)
  )[0];
  return latestImage;
};
