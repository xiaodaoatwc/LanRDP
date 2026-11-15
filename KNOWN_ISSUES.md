# Known Issues / 已知问题

## 1. Quality presets may not visibly differ on some RDP servers

**Status: unresolved / 暂时未解决**

### 中文

在部分 Windows/RDS 服务器上，“高质量 / 平衡 / 省流量”看起来差别很小，甚至没有区别。

典型例子：某些 Windows/RDS 服务器。

- 客户端请求 16/24/32bpp，但服务端返回 `RNS_UD_CS_WANT_32BPP_SESSION`，最终仍按 32bpp 会话运行；
- 图形编码由服务端选择。测试环境协商到 `RDPGFX_CODECID_CAPROGRESSIVE`，不会因为客户端加 `/gfx:AVC444` 就改用 AVC；
- 高质量和平衡目前主要差在 `/network` 和 `/bpp`，所以视觉效果可能相同；
- 省流量能看到区别，是因为 `-themes -wallpaper -menu-anims` 真正生效。

当前缓解办法：

- 省流量档关闭壁纸/主题/菜单动画；
- 需要明显降低带宽时，手动选择更低分辨率；
- 色深测试图在 `build/LanRDP-quality-test.png`。

后续方向：

- 让省流量档限制最大分辨率；
- 用性能选项而不是只靠 bpp 区分档位；
- 在支持 AVC 的服务器上再评估 codec 档位。

### English

On some Windows/RDS servers, “High quality / Balanced / Data saver” look nearly identical, or show no visible difference.

Typical example: some Windows/RDS servers.

- The client requests 16/24/32bpp, but the server returns `RNS_UD_CS_WANT_32BPP_SESSION`, so the session still runs at 32bpp.
- Graphics codec selection is server-driven. In the test environment it negotiated `RDPGFX_CODECID_CAPROGRESSIVE`; adding `/gfx:AVC444` on the client does not force AVC.
- High and Balanced currently differ mainly in `/network` and `/bpp`, so they can look the same.
- Data saver is visibly different because `-themes -wallpaper -menu-anims` actually take effect.

Current workarounds:

- Use Data saver to disable wallpaper/themes/menu animations.
- Manually choose a lower resolution when bandwidth is the main concern.
- A color-depth test chart is available at `build/LanRDP-quality-test.png`.

Planned direction:

- Cap the maximum resolution in Data saver.
- Distinguish presets with performance options rather than bpp alone.
- Re-evaluate codec presets on servers that support AVC.

## 2. macOS ad-hoc signing

**Status: known limitation / 已知限制**

The app is ad-hoc signed, not notarized by Apple. If macOS blocks the first launch, right-click the app and choose Open, or remove the quarantine attribute.

App 使用 ad-hoc 签名，未经过 Apple 公证。首次启动被拦截时，可右键选择“打开”，或移除 quarantine 属性。

## 3. Windows 10 主机上任务管理器图表不刷新（主机侧）

**Status: not a client issue / 非客户端问题**

某些 Windows 10 主机（已确认一台：旧款 ThinkPad + Intel 核显）在远程会话里，任务管理器“性能”页的图表会停住不动；同一台客户端连接 Windows Server 2025 时图表正常。

关键验证：**用微软 Remote Desktop 连接同一台 Windows 10，图表同样不动**。因此不是 LanRDP / FreeRDP 的问题，而是主机侧（DWM/显卡驱动/任务管理器的渲染路径）的问题。

可尝试的主机侧检查：

- 任务管理器 → 查看 → 更新速度，确认不是“暂停”；
- 更新 Intel 显卡驱动；
- 关闭“硬件加速 GPU 计划”（设置 → 系统 → 显示 → 图形设置），重启后再试；
- 升级到 Windows 10 22H2 的最新补丁；
- 在物理控制台上观察同一页图表是否正常，用于区分“仅远程会话”还是“本机也不刷新”。

Some Windows 10 hosts (observed on an older ThinkPad with Intel integrated graphics) stop updating the Task Manager performance graphs inside a remote session, while the same client works fine against Windows Server 2025.

Key check: Microsoft Remote Desktop shows the same frozen graphs on that host, so this is a host-side rendering issue (DWM / GPU driver / Task Manager), not a LanRDP or FreeRDP bug.

Host-side things worth trying:

- Task Manager → View → Update speed: make sure it is not Paused;
- Update the Intel graphics driver;
- Disable “Hardware-accelerated GPU scheduling”, reboot and retry;
- Update Windows 10 to the latest 22H2 patch level;
- Compare with the physical console: does the graph update there?
