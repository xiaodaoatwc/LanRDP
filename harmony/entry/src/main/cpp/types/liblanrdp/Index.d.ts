export const add: (a: number, b: number) => number;
export const version: () => string;
export const freerdpVersion: () => string;
export const connect: (host: string, port: number, username: string, password: string, domain: string, width: number, height: number, desktopScale: number, deviceScale: number) => Promise<string>;
export interface FrameTile {
  x: number;
  y: number;
  width: number;
  height: number;
  offset: number;
  stride: number;
}
export interface Frame {
  width: number;
  height: number;
  version: number;
  full: boolean;
  tiles: FrameTile[];
  data: ArrayBuffer;
}
export interface SessionInfo {
  state: number;
  error: string;
  version: number;
  width: number;
  height: number;
}
export const stopSession: () => boolean;
export const getSessionInfo: () => SessionInfo;
export const getFrame: () => Frame | null;
export const sendMouse: (x: number, y: number, button: number, down: boolean) => boolean;
export const sendWheel: (delta: number) => boolean;
export const sendUnicode: (code: number, down: boolean) => boolean;
export const sendKey: (code: number, down: boolean, extended: boolean) => boolean;
export const sendMouseMove: (x: number, y: number, button: number) => boolean;
