export const add: (a: number, b: number) => number;
export const version: () => string;
export const freerdpVersion: () => string;
export const connect: (host: string, port: number, username: string, password: string, domain: string) => Promise<string>;
export interface Frame {
  width: number;
  height: number;
  version: number;
  data: ArrayBuffer;
}
export const stopSession: () => boolean;
export const getFrame: () => Frame | null;
export const sendMouse: (x: number, y: number, button: number, down: boolean) => boolean;
export const sendWheel: (delta: number) => boolean;
export const sendUnicode: (code: number, down: boolean) => boolean;
export const sendKey: (code: number, down: boolean, extended: boolean) => boolean;
export const sendMouseMove: (x: number, y: number, button: number) => boolean;
