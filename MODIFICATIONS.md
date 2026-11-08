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

补丁文件位于 `patches/`，可在 FreeRDP 源码根目录执行：

```bash
patch -p1 < patches/0001-sdl-utils-sdl3420.patch
patch -p1 < patches/0002-macos-display-query.patch
patch -p1 < patches/0003-askpass-repeated.patch
```

修改日期：2026-11-08。
