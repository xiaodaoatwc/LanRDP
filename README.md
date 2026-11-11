# LanRDP

[English](README.en.md) | 简体中文 | [更新日志 / Changelog](CHANGELOG.md) | [已知问题 / Known issues](KNOWN_ISSUES.md)

一个局域网 RDP 的 macOS 小工具，底层使用 **FreeRDP 3.33.0** 的 `sdl-freerdp`。
它不依赖 Microsoft 账号，也没有 Windows App 那套联网健康检查。
只要目标 Windows 的 3389 端口可达，局域网和广域网都可以连接；广域网通常需要端口映射、VPN 或内网穿透。

## 1.14 更新 / What's New

### 中文

- 每台 PC 新增画质档：自动 / 高质量 / 平衡 / 省流量，默认自动。
- 自动档在连接前探测 RTT 和抖动；VPN/公网最高使用平衡，不确定时使用平衡。
- 手动选择后按手动档位连接；新建 PC 默认自动。
- 左侧新增“最常访问”，按累计访问次数排序，可在设置中隐藏。
- 未分组的电脑自动归入“未分组”虚拟分组。
- 单击 PC 卡片会显示选中边框，双击仍然连接。

### English

- Added per-PC quality presets: Auto / High quality / Balanced / Data saver, default Auto.
- Auto probes RTT and jitter before connecting; VPN/public connections are capped at Balanced, and uncertain results fall back to Balanced.
- Manual selections are remembered per PC; new PCs default to Auto.
- Added “Most visited” in the sidebar, sorted by total connection count; can be hidden in Settings.
- PCs without a group are collected under the virtual “Ungrouped” group.
- Clicking a PC card highlights it; double-click still connects.

## 1.13 更新 / What's New

### 中文

- 中英双语界面：跟随系统 / 简体中文 / English。
- 设置页可切换语言，立即生效。
- 新增英文 README：`README.en.md`。

### English

- Bilingual UI: Follow System / Simplified Chinese / English.
- Language can be switched in Settings and takes effect immediately.
- Added an English README: `README.en.md`.

完整双语更新日志见 **[CHANGELOG.md](CHANGELOG.md)**。

## 1.12 更新

- 钥匙串条目增加可读标签，例如 `LanRDP: P410`、`LanRDP: T450S`。
- 设置页增加“打开钥匙串访问”按钮。

## 1.11 更新

- 全屏切回窗口时，窗口会按可见桌面大小恢复，避开 Dock 和菜单栏。
- 同时处理 FreeRDP 快捷键退出和 macOS 原生全屏退出两条路径。
- 显式发送 100% DPI，修复远程桌面图标异常放大。
- “使用可见桌面（不含 Dock）”按钮。

## 1.10 更新

- PC 增加“管理员会话（/admin）”开关，等价于 `mstsc /admin`。
- 适用于安装了 RDS 角色但没有可用 CAL 的服务器，例如 HNK-SV-MES103。
- 需要登录账户具备管理员权限。

## 1.9 更新

- 隐藏 FreeRDP 自带的连接进度小窗。
- 主 RDP 窗口先隐藏，等首帧画面绘制完成后再显示，去掉连接时的黑屏闪窗。
- 保留 1.8 的许可/传输失败检测和简短错误提示。

## 1.8 更新

- 增加 RDP 许可/传输阶段失败的检测，HNK-SV-MES103 这类“连接后立刻关闭、没有弹窗”的情况现在会提示。
- 失败弹窗不再依赖进程退出码，即使 FreeRDP 以 0 退出，只要日志里有明确失败也会提示。

## 1.7 更新

- 连接失败提示改为简短分类：登录失败、端口拒绝、连接超时、证书变化、TLS 握手失败等。
- 弹窗不再直接贴大段 FreeRDP 日志；需要时点“查看日志”打开日志文件夹。

## 1.6 更新

- 新增 Universal 构建：Apple Silicon（arm64）和 Intel（x86_64）都能运行，版本号仍为 1.6。
- README 改为“局域网 RDP 的 macOS 小工具”；补充广域网访问说明。
- 默认证书策略改为“忽略证书错误”，不再首次信任/弹证书提示；首次信任仍保留为高级选项。
- 更新 GitHub 远程地址：`https://github.com/xiaodaoatwc/LanRDP.git`。

## 1.5 更新

- 增加 MIT `LICENSE`，版权人：`xiaodaoatwc`。
- App 和 DMG 内也包含 `LICENSE`。

## 1.4 更新

- App 内打包第三方许可证全文和修改说明；设置页可打开。
- 生成 FreeRDP 修改补丁，方便复核 Apache-2.0 下的修改。
- 初始化本地 Git 仓库和本地 bare remote（见“本地 Git”）。

## 1.3 更新

- 修复已保存密码仍被 FreeRDP 多次询问：现在通过 `FREERDP_ASKPASS` 临时助手在每次认证提示时提供同一密码，而不是只喂一次 stdin。
- 密码仍不出现在进程参数里；askpass 临时文件权限 0600，会话结束即删除。
- 由于本地签名每次更新都会变化，macOS 钥匙串可能反复要求授权。密码会同时写入一个权限为 0600 的本地 fallback 文件，读取时优先用它，避免每次连接都弹密码框。文件位置：`~/Library/Application Support/LanRDP/passwords-fallback.json`。如果不接受明文 fallback，可以删掉该文件；钥匙串里仍有副本。

## 1.2 更新

- 修复窗口模式启动时“闪一下全屏”：FreeRDP 在 macOS 上用了一个会短暂全屏的虚拟窗口来查询显示器，已改为直接读取显示器信息。
- 修复全屏模式初始分辨率/任务栏显示异常：现在启动时按真实显示器尺寸建立会话。
- 增加常用分辨率预设和“使用当前屏幕”。
- 缩放增加 125%、150%、175%、200%；FreeRDP 原生 140%/180% 仍保留。

## 打开

已构建好的 App：

```text
lanrdp/build/LanRDP.app
```

双击打开。因为这是本地 ad-hoc 签名的 App，没有经过 Apple 公证；如果 macOS 第一次拦截，右键点击 App →“打开”，或者在终端执行：

```bash
xattr -dr com.apple.quarantine lanrdp/build/LanRDP.app
```

## 使用

1. 点 **添加 PC**。
   - 填 Windows 的 IP 和端口（默认 3389）
   - 凭据默认是 **“直接输入”**：填用户名（域可选），连接时输入密码即可，不需要先新建凭据
   - 需要的话调整显示、Retina 缩放、共享文件夹
2. 如果多台电脑用同一个账户，可以先去 **凭据** 新建一套共享凭据，再在 PC 里选择它。
   - 名称：随便起，例如“办公室账户”
   - 用户名：Windows 用户名
   - 域：可选，例如 `DESKTOP-ABC`
   - 密码：保存在 macOS 钥匙串；留空则连接时询问
3. 点 **连接**。第一次连接会根据证书策略处理证书。
4. 直接输入的密码可以选择保存在钥匙串，仅该 PC 使用；共享凭据的密码则由多台 PC 共用。

## 功能

- 添加/编辑/删除 PC
- 自定义分组；删除分组不会删除 PC
- 直接用户名/密码登录（默认），无需先建凭据
- 共享凭据，密码保存在 macOS 钥匙串
- 显示模式：窗口、全屏、固定分辨率
- 常用分辨率预设（720p、1080p、1440p、4K 等）和“使用当前屏幕”
- 动态分辨率
- Retina/高 DPI：100%、125%、150%、175%、200%（另保留 FreeRDP 原生 140%/180%）
- 多显示器
- 剪贴板、声音
- 共享本地文件夹（Windows 中显示为 `\\tsclient\MacShare`）
- 证书策略：忽略证书错误（默认，无提示）、首次信任、严格校验
- 额外 FreeRDP 参数
- 连接日志，失败时自动提示

## 数据位置

```text
~/Library/Application Support/LanRDP/config.json
~/Library/Application Support/LanRDP/Logs/
```

密码不在 `config.json` 里，而是在 macOS 钥匙串，服务名为 `com.lanrdp.credentials`。

## 实现说明

- `sdl-freerdp` 和 OpenSSL 动态库已经打进 App 包，移动到别的 Mac 也能用。
- 密码通过 `/from-stdin:force` 从标准输入传给 FreeRDP，不出现在进程参数里。
- Retina 200% 使用 `/scale-desktop:200` + `/scale-device:180`；FreeRDP 的 `/scale` 本身只接受 100/140/180。
- 连接失败时，程序会读取 FreeRDP 日志并结束卡住的客户端进程，然后把错误显示在 App 里。

## 重新构建

```bash
cd lanrdp
./build.sh
```

`build.sh` 使用 `.build` 中已经编译好的 `sdl-freerdp`。如果要重新编译 FreeRDP，需要：

- CMake
- OpenSSL 3
- SDL3 3.4.20（静态库）
- SDL3_ttf 3.2.2（静态库，FreeType 2.15.0）

当前 `.build` 中已经包含这些依赖和 FreeRDP 源码构建产物。

## 保存的密码不对

- 直接登录：编辑这台 PC，点 **“清除此电脑保存的密码”**，下次连接会重新询问。
- 共享凭据：编辑左侧“凭据”里的对应项，输入新密码保存。

## 证书变化 / 退出时报错

- 正常关闭远程桌面窗口不会弹“连接失败”。程序只在日志里检测到真正的连接失败、认证失败、3389 拒绝或证书主机密钥变化时才提示。
- 如果提示“证书已变化 / Host key verification failed”，通常是 Windows 重装、重置远程桌面或换了机器。编辑这台 PC，点 **“清除此电脑的证书缓存”**，然后重新连接；也可以临时把证书策略改成“忽略证书错误”。

## 已知限制

- 这是本地签名 App，不是 Apple 公证版本。
- 面向 Windows 远程桌面，可用于局域网或广域网；不支持 Azure Virtual Desktop、Windows 365 等云资源。
- FreeRDP 的显示缩放取决于 Windows 版本和桌面会话，200% 不保证所有应用都完美。
- 默认“忽略证书错误”不会弹出证书信任提示；如果启用“首次信任”，证书变化时可能拒绝连接，可在 PC 设置里改回忽略或清除证书缓存。

## 第三方组件与许可证

- FreeRDP 3.33.0 — Apache License 2.0（已修改，见 `MODIFICATIONS.md` / `patches/`）
- SDL3 3.4.20 / SDL3_ttf 3.2.2 — zlib License
- OpenSSL 3.3.1 — Apache License 2.0
- FreeType 2.15.0 — FreeType License（FTL），另附 GPLv2 文本

完整的许可证文本在 `Resources/Licenses/`，规则说明在 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
App 内“设置 → 开源许可”也可以直接打开。

## 本地 Git

项目本身是一个 Git 仓库，另外在上一级目录创建了本地 bare remote：

```text
lanrdp-local.git
```

查看历史：

```bash
cd lanrdp
git log --oneline
git remote -v
```

推送到本地 remote：

```bash
git push origin main
```

## License

LanRDP 原始代码使用 MIT License，版权人：

```text
Copyright (c) 2026 xiaodaoatwc
```

完整文本见 [LICENSE](LICENSE)。FreeRDP、OpenSSL、SDL3、SDL3_ttf、FreeType 等第三方组件仍按各自许可证分发，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
