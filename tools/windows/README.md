# Windows 键盘/输入法诊断工具

用于对比 **物理键盘** 和 **LanRDP HarmonyOS 客户端** 发到 Windows 的按键序列，定位 Shift 大小写、中英文切换不一致的问题。

## 运行

在 **Windows 远程桌面内**（不是 HarmonyOS）打开 PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File KeyDiag.ps1
```

不需要管理员权限。工具会：

- 安装低级键盘钩子，记录每一次按键的 key down / key up；
- 记录虚拟键码、扫描码、扩展键、注入标记；
- 记录 Shift / Ctrl / Alt / Caps Lock 状态；
- 记录前台窗口、实际焦点控件；
- 记录当前 IME 是否打开、是否处于中文（native）模式。

日志写在脚本旁边：

```text
keydiag-YYYYMMDD-HHmmss.log
```

关闭 PowerShell 窗口即停止。

## 怎么测

1. 启动脚本。
2. **点击目标窗口**（例如记事本或 Office），让目标窗口获得焦点；不要停在 PowerShell。
3. 确认 Windows 当前是**英文输入状态**。
4. **按 `F9` 写一条 `# MARK` 分隔线**，然后再做每一组测试。建议顺序：
   - `F9` → 物理键盘：按住 Shift 输入 `A`，松开 A，再松开 Shift；记录语言栏是“中”还是“英”；
   - `F9` → 客户端 `Shift原生`：同一组动作；
   - `F9` → 客户端 `Shift兼容`：同一组动作；
   - `F9` → 单独按一下 Shift，记录语言栏变化。
5. **如果要对比原生按键序列**：在 HarmonyOS 客户端顶部把 `Shift兼容` 切成 `Shift原生`。兼容模式下字母通过 Unicode 发送，日志里会看到 `VK_PACKET(U+0041)` 这类事件，而不是 `scan=0x1E`。
6. 每次测试前先清空文本，尽量不要在 Shift+A 前额外按 Shift，否则会把“单独的 Shift 点击”混进来。

把日志片段发回来即可。重点看：

| 字段 | 含义 |
|---|---|
| `DOWN` / `UP` | 按下 / 松开 |
| `vk=0x..` | Windows 虚拟键码 |
| `scan=0x..` | 扫描码；Shift=0x2A/0x36，A=0x1E |
| `shift=1` | 该事件发生时 Shift 处于按下状态 |
| `imeOpen=1` | 输入法处于打开状态 |
| `imeNative=1` | 输入法处于中文（native）模式；0 为英文模式 |
| `conv=0x....` | IMM conversion mode 原始值 |
| `imeOk=0` | 当前窗口没有 IMM 上下文（常见于 TSF 输入法），此时以语言栏观察为准 |
| `hkl=0x....` | 前台窗口线程的键盘布局 ID，例如 0x0804 / 0x0409 |
| `imeMsg=0x....` | 通过 `WM_IME_CONTROL / IMC_GETCONVERSIONMODE` 读到的值，部分输入法不支持 |
| `VK_PACKET(U+0041)` | 通过 `SendInput`/RDP 发送的 Unicode 字符 `A`，不是物理扫描码 |
| `INJECTED` | 事件来自注入（RDP 客户端输入通常会带这个标记） |
| `fg/focus` | 前台窗口和实际焦点控件 |

## 判读方法

### 情况 A：物理键盘 `Shift+A` 也把 `imeNative` 从 0 变成 1

说明这是 Windows 输入法本身的 Shift 切换行为，不是客户端事件顺序问题。

客户端要同时满足“Shift+A 不切输入法”和“单独 Shift 切输入法”，只能：

- 对字母/符号使用 Unicode 输入（不发送真实 Shift），单独 Shift 再发送一次 Shift 点击；或者
- 在 Windows 输入法设置里把中英文切换改成 `Ctrl+Space` 等其他快捷键，客户端继续发送真实 Shift。

### 情况 B：物理键盘不切换，只有客户端切换

对比两次日志的 **事件顺序**：

- 客户端是否在 `A DOWN` 之前就出现了 `SHIFT UP`？
- 是否只有 `SHIFT DOWN` + `A DOWN`，但缺少 `SHIFT UP`？
- `INJECTED` 事件的时间间隔是否异常？
- `scan` 是否与物理键盘一致（Shift 0x2A、A 0x1E）？

如果顺序/时序不同，可以在客户端侧调整 Shift 的发送时机或顺序，而不必放弃原生 Shift。

## 注意

- 日志会包含窗口标题，可能包含文档名；分享前请自行检查、脱敏。
- 不要在这个工具里输入密码；它只记录按键，不记录文本内容，但按键本身可能包含敏感信息。
- 工具只用于本机诊断，不联网、不上传。
