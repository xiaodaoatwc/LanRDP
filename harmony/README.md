# LanRDP HarmonyOS

HarmonyOS NEXT client for LanRDP.

## Status

- DevEco Studio 26 / OpenHarmony API 26
- Stage model, ArkTS UI
- Native NAPI bridge `liblanrdp.so`
- OpenSSL 3.3.1 and FreeRDP 3.33.0 cross-compiled for:
  - `arm64-v8a`
  - `x86_64`
- FreeRDP is statically linked into `liblanrdp.so`; the HAP does not need a separate FreeRDP binary.

## Native bridge

```typescript
import { add, version, freerdpVersion } from 'liblanrdp.so';
```

Current smoke API:

```text
version()         -> 0.1.0
freerdpVersion()  -> 3.33.0
```

## Local dependency prefixes

The build expects locally built OHOS dependency prefixes under the worktree:

```text
../.build/ohos/prefix-arm64
../.build/ohos/prefix-x86_64
../.build/ohos/prefix-freerdp-arm64
../.build/ohos/prefix-freerdp-x86_64
```

They are intentionally not committed to Git.

## Build

```bash
export NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node
export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
export PATH="$NODE_HOME/bin:$PATH"

/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  assembleHap --mode module \
  -p product=default \
  -p module=entry@default \
  -p buildMode=debug --no-daemon
```

Output:

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
```

## Signing

In DevEco Studio:

```text
File → Project Structure → Project → Signing Configs
```

Select the `entry` module / `default` product, enable **Automatically generate signature**, and sign in with a Huawei developer account.

For a real device, enable developer mode and USB debugging first. DevEco creates the debug signing material and adds a `signingConfigs` entry to `build-profile.json5`.

Do not commit generated `.p12`, `.cer`, `.p7b`, or `.csr` files; they are ignored by `harmony/.gitignore`.

## Next

1. Add FreeRDP session lifecycle to NAPI.
2. Add a framebuffer callback and an ArkUI XComponent renderer.
3. Add input, clipboard, display resize, and certificate handling.
4. Add OpenSSL/FreeRDP license notices to the HAP.
