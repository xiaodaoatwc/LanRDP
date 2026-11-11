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
