import { image } from '@kit.ImageKit';

export const add: (a: number, b: number) => number;
export const version: () => string;
export const freerdpVersion: () => string;
export const connect: (host: string, port: number, username: string, password: string, domain: string, width: number, height: number, desktopScale: number, deviceScale: number) => Promise<string>;
export interface Frame {
  width: number;
  height: number;
  version: number;
  data: ArrayBuffer;
}
export interface SessionInfo {
  state: number;
  error: string;
  version: number;
  width: number;
  height: number;
  frameIndex: number;
  nativeBound: boolean;
}
export const stopSession: () => boolean;
export const getSessionInfo: () => SessionInfo;
export const getFrame: () => Frame | null;
export const bindFrameMaps: (first: image.PixelMap, second: image.PixelMap, third: image.PixelMap) => boolean;
export const unbindFrameMaps: () => boolean;
export const sendMouse: (x: number, y: number, button: number, down: boolean) => boolean;
export const sendWheel: (delta: number) => boolean;
export const sendUnicode: (code: number, down: boolean) => boolean;
export const sendKey: (code: number, down: boolean, extended: boolean) => boolean;
export const sendMouseMove: (x: number, y: number, button: number) => boolean;
