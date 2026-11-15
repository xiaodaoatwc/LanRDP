# HarmonyOS 渲染与视频管线

> 最近更新：2026-11-15。适用于 `harmonyos` 分支当前实现。

## 1. 当前架构

- FreeRDP 3.33.0，静态链接进 `liblanrdp.so`。
- H.264 当前使用 **OHOS 原生 AVCodec**（AVC420，硬件解码，`WITH_OHOS_AVCODEC=ON`）。
- 自建 LGPL-only FFmpeg 9.0.2 保留为回退方案，不随当前 HAP 分发。
- 客户端使用 core context，但补上：
  - `instance->LoadChannels = freerdp_client_load_channels`
  - `freerdp_register_addin_provider(freerdp_channels_load_static_addin_entry, 0)`
  - 订阅 `PubSub_SubscribeChannelConnected`，收到 rdpgfx 后调用
    `gdi_graphics_pipeline_init()`。
- 动态通道：`drdynvc` 由 `freerdp_client_load_addins()` 在
  `SupportDynamicChannels=TRUE` 时加载。
- 显示：
  - 默认：native PixelMap 三缓冲 + display ack + Image。
  - X 模式：XComponent + EGL/GLES，`eglSwapInterval(1)`，纹理上传/绘制。
- 帧合并：`SessionEndPaint()` 只置 pending；`FlushNativeFrame()` 约 16ms 将最新
  GDI 画面写一次 PixelMap/CPU 缓冲。
- X 路径已接 dirty rects：从 `gdi->primary->hdc->hwnd->cinvalid` 收集，只拷贝/上传
  变化区域；首帧、缩放变化、dirty 超限时回退整帧。视频本身接近全屏，收益有限；
  滚动/局部更新收益更明显。
- X 的 `viewOffset` 从 vp 按 Surface/视图尺寸换算成物理像素，修复缩放后点击偏移。

## 2. 构建

FFmpeg：

```bash
./harmony/scripts/ffmpeg-lgpl-ohos.sh
```

产物：`.build/ohos/prefix-ffmpeg-arm64/`。

FreeRDP（FFmpeg 版）：

```bash
./harmony/scripts/build-freerdp-ffmpeg-ohos.sh
```

产物：`.build/ohos/prefix-freerdp-arm64-ffmpeg/`。

App 侧 CMake 会链接：

- `libfreerdp3.a`
- whole-archive `libfreerdp-client3.a`
- `remdesk-common` / `rdpsnd-common`
- FFmpeg 三个 `.so`（随 HAP 打包到 `libs/arm64-v8a/`）

## 3. 已验证结果

- GFX 通道可建立；服务器协商到 `RDPGFX_CODECID_AVC420`；
- H264 解码正常，画面正常；
- 非 X / X 模式均无撕裂；
- 服务端 GFX 输出约 30–32fps，不是客户端限帧；
- 连接时间已比早期版本缩短；
- X 模式视频 CPU 约 174–237%（平均约 210%），非 X 约 110–233%（平均约 168%）；
- dirty rects 对全屏视频收益很小，对局部更新有效。

## 4. 回退

- FFmpeg/GFX 路径出问题时，可改回旧 `prefix-freerdp-arm64` 并关闭
  `SupportGraphicsPipeline`，恢复位图路径（旧版本有撕裂/卡顿，但可用）。
- 源码签名配置 `harmony/build-profile.json5` 只保留本地，不提交。

## 5. 待办

- 30fps 是当前服务端 GFX 节奏；若需 60fps，需要硬件解码或服务端策略调整。
- 连接时间仍可继续优化。
- 非 X 的 PixelMap 三缓冲 dirty 写入尚未实现；当前保持整帧。
