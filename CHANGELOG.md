# Changelog / 更新日志

All notable changes to LanRDP are documented here.
LanRDP 的主要变更记录在这里。

## 1.14.1 — 2026-11-13

### 中文

- 修复右 Shift 组合键被 FreeRDP 客户端快捷键截获的问题：
  右 Shift+D 会直接断开连接，右 Shift+G / 右 Shift+R 打不出对应的大写字母，
  右 Shift+M 会把窗口最小化。
- 客户端快捷键的修饰键从“单独的右 Shift”改为“左 Ctrl + 左 Alt”，
  正常输入大写字母不再被截获；全屏切换等快捷键相应变为左 Ctrl + 左 Alt + 按键。

### English

- Fixed right Shift combinations being captured by the FreeRDP client shortcuts:
  right Shift+D disconnected the session, right Shift+G/R swallowed the capital letters,
  and right Shift+M minimized the window.
- Client shortcuts now require left Ctrl + left Alt instead of a lone right Shift, so typing
  capital letters always reaches the remote desktop. Fullscreen and the other shortcuts
  become left Ctrl + left Alt + key.

## 1.14 — 2026-11-11

### 中文

- 新增每台 PC 的画质档：自动 / 高质量 / 平衡 / 省流量，默认自动。
- 自动档在连接前探测 RTT、抖动和路径类型；VPN/公网最高使用平衡，不确定时回退平衡。
- 手动选择后按手动档位连接；新建 PC 默认自动。
- 高质量：`/network:lan`、32bpp；平衡：`/network:auto`、24bpp；省流量：`/network:wan`、16bpp、NSC、关闭壁纸/主题/菜单动画。
- 修复窗口模式连接时指定分辨率被可见桌面大小覆盖的问题。
- 画质档在部分服务器上看不出差异，记录在 `KNOWN_ISSUES.md`。
- 左侧新增“最常访问”，按累计访问次数排序，可在设置中隐藏。
- 未分组 PC 自动归入“未分组”虚拟分组。
- 单击 PC 卡片显示选中样式，双击仍然连接。
- 支持把 PC 拖放到左侧分组或“未分组”；右键菜单也提供“移动到分组”。

### English

- Added per-PC quality presets: Auto / High quality / Balanced / Data saver, default Auto.
- Auto probes RTT, jitter, and path type before connecting; VPN/public connections are capped at Balanced, with Balanced as the fallback.
- Manual selections are remembered per PC; new PCs default to Auto.
- High: `/network:lan`, 32bpp; Balanced: `/network:auto`, 24bpp; Data saver: `/network:wan`, 16bpp, NSC, wallpaper/themes/menu animations disabled.
- Fixed the specified resolution being replaced by the visible desktop size in windowed mode.
- Quality presets may look identical on some servers; documented in `KNOWN_ISSUES.md`.
- Added “Most visited” in the sidebar, sorted by total connection count; can be hidden in Settings.
- Ungrouped PCs are collected under the virtual “Ungrouped” group.
- Clicking a PC card highlights it; double-click still connects.
- Drag a PC onto a sidebar group or “Ungrouped”; the context menu also has “Move to group”.

## 1.13 — 2026-11-09

### 中文

- 中英双语界面：跟随系统 / 简体中文 / English。
- 设置页可切换语言，立即生效。
- 主要界面、表单、错误提示和弹窗完成英文翻译。
- 新增英文 README：`README.en.md`。

### English

- Bilingual UI: Follow System / Simplified Chinese / English.
- Language can be switched in Settings and takes effect immediately.
- Translated the main UI, forms, errors, and dialogs into English.
- Added an English README: `README.en.md`.

## 1.12 — 2026-11-09

### 中文

- 钥匙串条目标签改为可读名称，例如 `LanRDP: Office-PC`、`LanRDP: Laptop`。
- 钥匙串描述区分共享凭据和单机密码。
- 设置页新增“打开钥匙串访问”。

### English

- Keychain items now have readable labels, such as `LanRDP: Office-PC` and `LanRDP: Laptop`.
- Keychain descriptions distinguish shared credentials from per-PC passwords.
- Added “Open Keychain Access” to Settings.

## 1.11 — 2026-11-09

### 中文

- 全屏切回窗口时按可见桌面恢复，避开 Dock 和菜单栏。
- 同时处理 FreeRDP 快捷键退出和 macOS 原生全屏退出。
- 显式发送 100% DPI，修复远程桌面图标异常放大。
- 新增“使用可见桌面（不含 Dock）”按钮。

### English

- Restoring from full screen now uses the visible desktop, avoiding the Dock and menu bar.
- Handles both FreeRDP's fullscreen shortcut and native macOS fullscreen exit.
- Sends an explicit 100% DPI to fix oversized remote desktop icons.
- Added “Use visible desktop (excluding Dock)”.

## 1.10 — 2026-11-09

### 中文

- PC 增加“管理员会话（/admin）”选项，等价于 `mstsc /admin`。
- 适用于安装了 RDS 角色但没有可用 CAL 的服务器。

### English

- Added an “Admin session (/admin)” option per PC, equivalent to `mstsc /admin`.
- Useful for RDS servers without an available CAL.

## 1.9 — 2026-11-09

### 中文

- 隐藏 FreeRDP 自带的连接进度小窗。
- 主 RDP 窗口先隐藏，等首帧画面绘制完成后再显示，去掉黑屏闪窗。

### English

- Hid FreeRDP's built-in connection progress window.
- Kept the main RDP window hidden until the first frame is painted, removing the black flash.

## 1.8 — 2026-11-09

### 中文

- 增加 RDP 许可/传输阶段失败检测。
- 失败弹窗不再依赖进程退出码。
- 错误提示改为简短分类，原始日志通过“查看日志”打开。

### English

- Added detection for RDP licensing/transport failures.
- Failure alerts no longer depend on the process exit code.
- Error alerts are now short and categorized; raw logs are available via “View log”.

## 1.7 — 2026-11-09

### 中文

- 连接失败提示按登录失败、端口拒绝、超时、证书变化、TLS 失败分类。
- 弹窗不再直接贴大段 FreeRDP 日志。

### English

- Connection errors are categorized as login failure, port refused, timeout, certificate change, or TLS failure.
- Dialogs no longer dump long FreeRDP logs.

## 1.6 — 2026-11-08

### 中文

- 默认证书策略改为“忽略证书错误”，不再弹首次信任提示。
- README 改为“局域网 RDP 的 macOS 小工具”，补充广域网说明。
- 新增 Universal 构建（Apple Silicon + Intel）。

### English

- Changed the default certificate policy to “Ignore certificate errors”; no trust prompt.
- Updated README to describe LAN/WAN use.
- Added a Universal build (Apple Silicon + Intel).

## 1.5 — 2026-11-08

### 中文

- 增加 MIT License，版权人 `xiaodaoatwc`。
- App 和 DMG 内包含许可证。

### English

- Added the MIT License, copyright `xiaodaoatwc`.
- Bundled the license in the app and DMG.

## 1.4 — 2026-11-08

### 中文

- App 内打包第三方许可证和 FreeRDP 修改说明。
- 生成 FreeRDP 修改补丁。
- 初始化本地 Git 仓库和 bare remote。

### English

- Bundled third-party licenses and FreeRDP modification notices.
- Added FreeRDP modification patches.
- Initialized the local Git repository and bare remote.

## 1.3 — 2026-11-08

### 中文

- 修复已保存密码仍被 FreeRDP 多次询问的问题。
- 使用 `FREERDP_ASKPASS` 临时助手在每次认证提示时提供密码。
- 增加 0600 本地密码 fallback，避免钥匙串反复授权。

### English

- Fixed repeated password prompts when a password was already saved.
- Added a temporary `FREERDP_ASKPASS` helper that answers every authentication prompt.
- Added a 0600 local password fallback to avoid repeated Keychain authorization.

## 1.2 — 2026-11-08

### 中文

- 修复窗口模式启动时闪全屏、全屏初始分辨率和任务栏显示异常。
- 增加常用分辨率预设和“使用当前屏幕”。
- 缩放增加 125%、150%、175%、200%。

### English

- Fixed fullscreen flashes, initial fullscreen resolution, and taskbar issues.
- Added common resolution presets and “Use current screen”.
- Added 125%, 150%, 175%, and 200% scaling.

## 1.1 — 2026-11-08

### 中文

- 支持不创建共享凭据，直接输入用户名和密码。
- 修复正常退出远程桌面后误报连接失败。
- 增加证书缓存清理。

### English

- Added direct username/password login without creating a shared credential.
- Fixed false connection errors after closing a remote desktop window normally.
- Added certificate cache clearing.

## 1.0 — 2026-11-08

### 中文

- 初始版本：PC 管理、分组、共享凭据、FreeRDP 连接、显示设置和文件夹共享。

### English

- Initial release: PC management, groups, shared credentials, FreeRDP connections, display settings, and folder sharing.
