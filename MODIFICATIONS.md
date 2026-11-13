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
```

修改日期：2026-11-08，2026-11-13 增补第 8 项。
