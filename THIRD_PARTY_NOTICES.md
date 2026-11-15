# LanRDP 第三方组件与许可证

LanRDP 的图形界面、配置管理和启动逻辑是原始代码；RDP 连接由 FreeRDP 提供。
App 包内包含以下第三方组件：

| 组件 | 版本 | 许可证 | 在 App 中的形式 |
|---|---|---|---|
| FreeRDP (`sdl-freerdp`) | 3.33.0 | Apache License 2.0 | 可执行文件，已修改 |
| SDL3 | 3.4.20 | zlib License | 静态链接 |
| SDL3_ttf | 3.2.2 | zlib License | 静态链接 |
| FreeType | 2.15.0 | FreeType License (FTL) 或 GPLv2 | 静态链接 |
| OpenSSL (`libssl`, `libcrypto`) | 3.3.1 | Apache License 2.0 | 动态库，随 App 分发 |
| FFmpeg (`libavcodec` 等) | 9.0.2 | GNU LGPL v2.1 or later | 动态库，随 App 分发（LGPL-only 构建，未启用 GPL 组件） |
| zlib | macOS 系统版本 | zlib License | 系统库 |
| Apple 系统框架 | macOS 14+ | Apple 系统许可 | 系统框架，不随 App 分发 |

## 许可证全文

- `Licenses/FreeRDP-LICENSE.txt`
- `Licenses/SDL3-LICENSE.txt`
- `Licenses/SDL3_ttf-LICENSE.txt`
- `Licenses/FreeType-FTL.txt`
- `Licenses/FreeType-GPLv2.txt`
- `Licenses/FreeType-LICENSE.txt`
- `Licenses/OpenSSL-LICENSE.txt`
- `Licenses/FFmpeg-LGPL-2.1.txt`

## 需要遵循的规则

### Apache License 2.0（FreeRDP、OpenSSL）

- 随分发物提供 Apache License 2.0 全文。
- 保留原作者的版权、专利、商标和归属声明。
- 如果修改了文件，需要在修改的文件中放置显著通知，说明文件被修改过。
- 如果原项目带有 `NOTICE` 文件，需要保留其中的归属声明。FreeRDP 3.33.0 没有单独的 `NOTICE` 文件。
- 不暗示原作者为 LanRDP 背书。
- 本次对 FreeRDP 的修改和原因见 `MODIFICATIONS.md` 与 `patches/`。

### zlib License（SDL3、SDL3_ttf、zlib）

- 不得歪曲原作者的来源。
- 如果修改了源码，需要显著标注修改，并且不得把修改版说成原版。
- 在文档或随附材料中保留版权和许可声明。
- 本 App 未修改 SDL3/SDL3_ttf 源码，只进行了静态链接。

### FreeType License（FreeType）

- 在文档中注明使用了 FreeType Project。
- 保留 FreeType 的版权和 FTL 许可文本。
- 如果选择 GPLv2 分支，则需要按 GPLv2 分发相应源码；本项目选择 FTL，并同时保留 GPLv2 文本供参考。
- 不暗示 FreeType 作者为 LanRDP 背书。

### GNU LGPL v2.1 or later（FFmpeg）

- App 内自带的是**自建的 LGPL-only FFmpeg**：`--disable-gpl --disable-nonfree`，
  只启用 H.264 解码、parser 和 swscale/swresample，未链接 x264/x265 等 GPL 组件。
- FFmpeg 以**动态库**形式随 App 分发（`Contents/Frameworks/libav*.dylib`），
  用户可以替换这些库文件；LanRDP 自身代码仍为 MIT，不因链接 LGPL 库而改变许可证。
- 随 App 提供 LGPL 全文与 FFmpeg 版权声明。
- 源码：对应上游源码为 `https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz`（未做任何修改），
  构建参数见本仓库 `scripts/ffmpeg-lgpl.sh`，可完全复现同样的 LGPL-only 配置；
  如需要也可以联系作者获取源码副本。
- 替换 FFmpeg 库：LGPL 允许用户替换该库。把 `LanRDP.app/Contents/Frameworks/libav*.dylib`
  换成自己编译的版本后，执行
  `codesign --force --deep --sign - /Applications/LanRDP.app` 重新签名即可
  （LanRDP 未启用 hardened runtime）。
- 如果修改了 FFmpeg 源码，需要在修改文件中标注，并随分发提供修改后的源码。

### 商标

FreeRDP、SDL、OpenSSL、FreeType、Microsoft、Windows 等名称是其各自权利人的商标。
LanRDP 与这些项目没有隶属或背书关系。

## LanRDP 原始代码

LanRDP 自己的 SwiftUI、配置管理和启动逻辑使用 MIT License，
版权人：`Copyright (c) 2026 xiaodaoatwc`，全文见 `LICENSE`。
本文件主要覆盖第三方组件。

## 源码与修改

FreeRDP 源码位于构建目录 `.build/src/freerdp-3.33.0`，修改补丁位于 `patches/`。
LanRDP 自己的源码位于 `Sources/`，本地 Git 仓库保存了完整历史。
