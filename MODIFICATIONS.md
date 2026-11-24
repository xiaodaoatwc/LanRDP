# FreeRDP 3.33.0 修改说明

LanRDP 分发的 `sdl-freerdp` 基于 FreeRDP 3.33.0，包含以下本地修改。
这些修改仅用于 macOS 桌面兼容性和密码提示行为，不改变 RDP 协议实现。

## 1. `client/SDL/SDL3/sdl_utils.cpp`

- **修改**：把 `SDL_EVENT_WINDOW_SETTINGS_CHANGED`、`SDL_EVENT_GAMEPAD_CAPSENSE_*`、
  `SDL_EVENT_NOTIFICATION_ACTION_INVOKED` 的编译条件从 SDL 3.4.20 改为 SDL 3.5.0。
- **原因**：FreeRDP 3.33.0 假定 SDL 3.5 的事件常量，但当前构建使用 SDL 3.4.20；
  这些事件只用于日志名称映射，不影响连接。

## 2. `client/SDL/SDL3/sdl_window.cpp`

- **修改**：macOS 上 `SdlWindow::query` 和 `SdlWindow::rect` 直接使用
  `SDL_GetDesktopDisplayMode` / `SDL_GetDisplayBounds`，不再创建 64×64 的 dummy
  window 并调用 `SDL_SetWindowFullscreen(true)`。
- **原因**：dummy 窗口在 macOS 上会短暂进入全屏，造成窗口模式“闪一下全屏”，
  并可能让全屏会话拿到错误的初始显示器尺寸。

## 3. `client/SDL/SDL3/dialogs/sdl_dialogs.cpp`

- **修改**：`sdl_authenticate_ex` 在每次密码为空时都允许 `FREERDP_ASKPASS`
  或 `/from-stdin` 提供密码，不再受 `credentialsRead` 标志限制。
- **原因**：NLA 和后续登录阶段可能多次请求凭据。原逻辑只允许第一次从
  askpass/stdin 读取，后续会弹 SDL 密码框，导致用户重复输入。

## 4. `client/SDL/SDL3/sdl_context.cpp`

- **修改**：macOS 上创建主 RDP 窗口时默认隐藏；等待连接完成、并且收到第一帧实际画面后，
  先在隐藏状态下绘制，再调用 `SDL_ShowWindow`。
- **原因**：原来窗口先显示、后绘制，会先出现一个小黑窗/黑屏首帧。
- **配套**：LanRDP 启动参数增加 `-sdl-connection-dialog`，关闭 FreeRDP 自带的连接进度小窗；
  错误改由 LanRDP 自己弹出。

## 5. `client/SDL/SDL3/sdl_window.cpp`（全屏恢复窗口）

- **修改**：macOS 上从全屏切回窗口时，用 `SDL_GetDisplayUsableBounds` 取可见桌面，
  扣除窗口边框后设置窗口大小和位置。
- **原因**：原来的恢复尺寸可能覆盖 Dock（Dock 在左/右/下都会发生）。

## 6. `client/SDL/SDL3/sdl_disp.cpp`

- **修改**：收到 `SDL_EVENT_WINDOW_LEAVE_FULLSCREEN`（包括 macOS 原生全屏退出）时，
  调用 `SdlWindow::fitToUsableBounds()`。
- **原因**：只改 `fullscreen(false)` 覆盖不到 macOS 绿色按钮/原生全屏退出路径，
  这条事件路径同样需要把窗口限制在可见桌面内。

## 7. `client/SDL/SDL3/sdl_window.cpp`（只在实际退出全屏时调整窗口）

- **修改**：`fullscreen(false)` 只在窗口原本处于全屏状态时才调用 `fitToUsableBounds()`。
- **原因**：FreeRDP 初始化窗口模式时也会调用一次 `setFullscreen(false)`；原来的实现会把
  `/w`、`/h` 指定的窗口尺寸直接改成可见桌面大小，导致指定分辨率失效。

## 8. `client/SDL/SDL3/sdl_input.cpp`（客户端快捷键修饰键）

- **修改**：`SDL_KeyModMask` 的默认值从 `KMOD_RSHIFT` 改为 `KMOD_LCTRL` + `KMOD_LALT`。
- **原因**：FreeRDP 默认把单独的右 Shift 当作客户端快捷键修饰键，导致右 Shift 无法用于
  输入大写字母：右 Shift+D 会直接断开连接（`SDL_Disconnect`），右 Shift+G / 右 Shift+R
  被 `SDL_Grab` / `SDL_Resizeable` 截获所以打不出字母，右 Shift+M 会最小化窗口
  （`SDL_Minimize`）。改成左 Ctrl+左 Alt 后，正常打字不会再触发客户端快捷键。
- **注意**：快捷键判断是 `(mod & mask) == mask`，不能写聚合的 `KMOD_CTRL` / `KMOD_ALT`
  （它们同时包含左右两侧的位，真实按键永远匹配不上）；必须写左右具体的 `KMOD_LCTRL`、
  `KMOD_LALT`。因此右 Ctrl / 右 Alt 不会触发快捷键，会正常发送到远程桌面。

## 9. `client/SDL/SDL3/sdl_freerdp.cpp`（视频播放时窗口卡死）

- **修改**：`SDL_EVENT_USER_UPDATE` 每次事件只绘制一帧；如果同一事件期间已经堆积了更多
  damage，就把它们合并成一个外接矩形一次画完。
- **原因**：原来的实现用 `do { pop(); draw(); } while (!empty)` 把队列画空。服务器持续发帧
  （视频播放）时，主线程长期停在这个事件处理里，SDL 的鼠标/窗口事件得不到分发：远程画面还在动，
  但点击无效而且出现转菊花。改成“一事件一帧”后主线程能回到事件循环处理输入。

## 10. `client/common/cmdline.c`（`/bpp` 不应关闭图形管线）

- **修改**：`prepare_default_settings` 里解析 `/bpp` 时不再把 `garg` 置为 TRUE。
- **原因**：一旦命令行出现 `/gfx`、`/rfx` 或 `/bpp`，FreeRDP 就跳过“自动启用图形管线、
  H.264/AVC444 和 RemoteFX”的默认逻辑。LanRDP 的画质档总会传 `/bpp`，于是 **GFX 和 H.264
  被静默关掉**：服务器只能退回位图/Progressive，表现为任务管理器图表不刷新、视频卡顿撕裂；
  即使构建里带了 FFmpeg H.264 也用不到。`/bpp` 只是色深选项，不应算作“显式选择了编解码器”。

补丁文件位于 `patches/`，可在 FreeRDP 源码根目录执行：

```bash
patch -p1 < patches/0001-sdl-utils-sdl3420.patch
patch -p1 < patches/0002-macos-display-query.patch
patch -p1 < patches/0003-askpass-repeated.patch
patch -p1 < patches/0004-sdl-context-hidden-window.patch
patch -p1 < patches/0005-sdl-window-usable-bounds.patch
patch -p1 < patches/0006-sdl-disp-native-fullscreen-exit.patch
patch -p1 < patches/0007-sdl-window-fullscreen-only.patch
patch -p1 < patches/0008-sdl-input-hotkey-modifier.patch
patch -p1 < patches/0009-sdl-bounded-frame-draw.patch
patch -p1 < patches/0010-bpp-keeps-gfx-defaults.patch
patch -p1 < patches/0011-sdl-coalescing-yuv-overlay-vt-hw.patch
patch -p1 < patches/0012-logical-resolution-fullscreen-space.patch
```

## 11. SDL 渲染合并、VideoToolbox 硬件解码提示、可选 YUV 叠加

- **修改**：
  - `client/SDL/SDL3/sdl_context.cpp`、`sdl_window.cpp/.hpp`：一次更新内的脏矩形超过 32 个时
    合并成包围盒，一次 `SDL_UpdateTexture` 代替几十次小调用；仅在还有未处理更新时才合并 present；
  - `libfreerdp/codec/h264_videotoolbox.c`：显式请求硬件解码
    （`kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder`），并在建会话时记录
    一次是否使用硬件解码；
  - 可选的 AVC420 YUV 叠加渲染（`avc420_decompress_yuv` / `rdpGdi::avcYuvOverlay`），
    **默认关闭**，需环境变量 `LANRDP_AVC_YUV=1` 才启用；实验特性，未验证稳定。
- **原因**：窗口视频时每秒 1000+ 次小矩形上传，每次调用开销把有效带宽从 ~4.8GB/s 拖到 ~2.6GB/s；
  Apple Silicon 的 H.264 硬解需要显式提示才更有保障。
- **效果**：窗口视频上传耗时 72 → 43 ms/s（-40%），全屏 52 → 42 ms/s（-20%）。

## 12. 逻辑分辨率显示、原生全屏 Space、动态分辨率换算

- **修改**：
  - `client/SDL/SDL3/sdl_context.cpp`：全屏窗口改为先创建普通可缩放窗口、显示第一帧后再进全屏，
    让 macOS 使用**原生全屏 Space**（Dock / Mission Control 可以切换过去）；
  - 逻辑分辨率模式（`LANRDP_LOGICAL_MONITOR=1`）：强制本地缩放，缩放时保持宽高比、居中，
    并把窗口偏移同时用于绘制和输入换算；
  - `client/SDL/SDL3/sdl_disp.cpp`：Display Control 上报的显示器尺寸按 SDL 的窗口显示缩放
    换算成逻辑分辨率（Retina 2x → 除以 2），系统分辨率变化时原地调整会话分辨率。
- **原因**：高分屏上让远程桌面按 macOS 逻辑分辨率显示（Windows 截图 ≈ 逻辑尺寸、带宽低），
  同时支持 mstsc 那样的“不重连原地改分辨率”。
- **兼容性**：仅在该模式开启时生效，默认行为不变。

## 13. 证书提示交给主 App、窗口缩放跟随、全屏退出还原、DPI 缩放全模式生效

- **修改**：
  - `client/SDL/SDL3/dialogs/sdl_dialogs.cpp/.hpp`：证书校验失败时把主机、端口、主题、颁发者、
    指纹写入 `LANRDP_CERT_FILE` 并中止连接（由主 App 弹原生警告）；SDL 对话框文本与按钮
    按 `LANRDP_LANG` 本地化；显示前激活 App；
  - `client/SDL/SDL3/sdl_disp.cpp`：新增 1 秒尺寸轮询（macOS 全屏 Space 在系统分辨率变化时
    可能不产生窗口事件）；离开全屏时不再强制拉成可用区域，交给 SDL 恢复进入全屏前的尺寸；
  - `client/SDL/SDL3/sdl_context.cpp`：动态分辨率开启时跳过 `resizeToScale()`，避免窗口尺寸
    被拉回初始值导致会话分辨率回弹；
  - 主 App：证书警告改为 `NSAlert`（置顶），接受后保存 `sha256:` 指纹并在后续连接传入
    `/cert:fingerprint:sha256:<指纹>`；DPI 缩放（100/125/140…）在 HiDPI 模式下同样生效。
- **原因**：SDL 证书对话框是独立进程窗口，无法可靠置顶；拖动窗口时 `resizeToScale()` 会把窗口
  弹回初始尺寸；HiDPI 模式曾写死 `/scale:100`，导致缩放设置无效。
- **效果**：证书警告始终前置并可记住选择；窗口/全屏尺寸变化会同步远程分辨率；缩放档位生效。

## 14. 缩放滤波、固定分辨率窗口缩放、更新入口

- **修改**：
  - `client/SDL/SDL3/sdl_window.cpp`：按 `LANRDP_FILTER` 选择画面放大滤镜（线性/最近邻）；
    固定分辨率时用 `SDL_SetWindowAspectRatio` 锁定窗口宽高比，避免缩放后出现黑边；
  - `client/SDL/SDL3/sdl_disp.cpp`：按 `LANRDP_FIXED_SIZE` 把 Display Control 上报的布局
    固定为设置的分辨率，窗口缩放只做本地放大；
  - `client/SDL/SDL3/sdl_context.cpp`：`LANRDP_SCALE_TO_WINDOW` 下允许窗口缩放、强制本地缩放，
    并跳过 `resizeToScale()` 以免窗口被拉回初始尺寸；
  - 主 App：显示设置新增「缩放滤波」；固定分辨率不再乘显示倍数；设置新增「查找新版本」
    （打开 GitHub 发布页）；凭据列表新增行内删除按钮，删除后引用它的电脑回退为默认直接登录。
- **原因**：用户需要自行选择放大滤镜；固定分辨率此前会被 HiDPI 放大成 2 倍会话尺寸；
  凭据只能通过右键菜单删除、不易发现。
- **效果**：固定分辨率 1280×720 与窗口模式一致；窗口等比缩放无黑边；删除凭据有明确入口。

## 15. 全屏转场安全、HiDPI 首帧逻辑分辨率

- **修改**：
  - `client/SDL/SDL3/sdl_window.cpp`：不再用 `SDL_SetWindowAspectRatio(0, 0)` 清空宽高比
    （SDL 会转成 `setContentAspectRatio:NSMakeSize(0,0)`，macOS 在退出全屏转场中会 trap）；
    新增 `LANRDP_WINDOW_SIZE`，把窗口的点尺寸与初始桌面尺寸解耦；
  - `client/SDL/SDL3/sdl_disp.cpp/.hpp`：进入/退出全屏时不再立即操作窗口，
    记录事件时间并等待 Space 转场结束（2 秒冷却），由主线程空闲轮询再更新布局；
  - `client/SDL/SDL3/sdl_freerdp.cpp`：主事件循环空闲时调用显示轮询（替代定时器线程）；
  - 主 App：HiDPI 窗口/固定模式连接时用逻辑尺寸作为初始桌面，窗口点尺寸单独传入，
    首帧即为目标分辨率。
- **原因**：固定分辨率的宽高比约束在非固定窗口上也被设置，触发 AppKit 全屏转场 trap；
  HiDPI 先用物理像素建会话再由 Display Control 切换，启动时可见一次分辨率跳变。
- **效果**：全屏进出不再卡死/崩溃；HiDPI 窗口模式启动无高分辨率闪动。

修改日期：2026-11-08，2026-11-13 增补第 8 项，2026-11-15 增补第 9、10、11 项，
2026-11-17 增补第 12 项，2026-11-19 增补第 13 项，2026-11-20 增补第 14 项，
2026-11-24 增补第 15 项。
