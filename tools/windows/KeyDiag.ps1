# KeyDiag.ps1 - Windows-side keyboard/IME diagnostic for LanRDP HarmonyOS.
#
# Run on the Windows machine that the HarmonyOS client connects to:
#   powershell -ExecutionPolicy Bypass -File KeyDiag.ps1
#
# The tool installs a low-level keyboard hook and logs every key down/up with:
#   - virtual key / scan code / extended / injected flags
#   - Shift/Ctrl/Alt/Caps state
#   - IME open state and Chinese (native) conversion mode
#   - foreground window and focused control
#
# Click the target application after starting the tool, then compare a physical
# keyboard with the HarmonyOS client. The log is written next to this script.

$ErrorActionPreference = "Stop"

$source = @'
using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;

namespace KeyDiag
{
    public static class Program
    {
        private const int WH_KEYBOARD_LL = 13;
        private const int WM_KEYDOWN = 0x0100;
        private const int WM_KEYUP = 0x0101;
        private const int WM_SYSKEYDOWN = 0x0104;
        private const int WM_SYSKEYUP = 0x0105;
        private const uint LLKHF_EXTENDED = 0x01;
        private const uint LLKHF_INJECTED = 0x10;
        private const int VK_SHIFT = 0x10;
        private const int VK_CONTROL = 0x11;
        private const int VK_MENU = 0x12;
        private const int VK_CAPITAL = 0x14;
        private const int IME_CMODE_NATIVE = 0x0001;

        [StructLayout(LayoutKind.Sequential)]
        private struct KBDLLHOOKSTRUCT
        {
            public uint vkCode;
            public uint scanCode;
            public uint flags;
            public uint time;
            public UIntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct POINT
        {
            public int x;
            public int y;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MSG
        {
            public IntPtr hwnd;
            public uint message;
            public UIntPtr wParam;
            public IntPtr lParam;
            public uint time;
            public POINT pt;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct RECT
        {
            public int left;
            public int top;
            public int right;
            public int bottom;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct GUITHREADINFO
        {
            public uint cbSize;
            public uint flags;
            public IntPtr hwndActive;
            public IntPtr hwndFocus;
            public IntPtr hwndCapture;
            public IntPtr hwndMenuOwner;
            public IntPtr hwndMoveSize;
            public IntPtr hwndCaret;
            public RECT rcCaret;
        }

        private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

        private static LowLevelKeyboardProc proc = HookCallback;
        private static IntPtr hook = IntPtr.Zero;
        private static StreamWriter writer = null;
        private static string logPath = "";
        private static long seq = 0;
        private static object sync = new object();

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll")]
        private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr GetModuleHandle(string lpModuleName);

        [DllImport("user32.dll")]
        private static extern int GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

        [DllImport("user32.dll")]
        private static extern bool TranslateMessage(ref MSG lpMsg);

        [DllImport("user32.dll")]
        private static extern IntPtr DispatchMessage(ref MSG lpMsg);

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll")]
        private static extern bool GetGUIThreadInfo(uint idThread, ref GUITHREADINFO lpgui);

        [DllImport("user32.dll")]
        private static extern short GetAsyncKeyState(int vKey);

        [DllImport("user32.dll")]
        private static extern short GetKeyState(int nVirtKey);

        [DllImport("imm32.dll")]
        private static extern IntPtr ImmGetContext(IntPtr hWnd);

        [DllImport("imm32.dll")]
        private static extern bool ImmReleaseContext(IntPtr hWnd, IntPtr hIMC);

        [DllImport("imm32.dll")]
        private static extern bool ImmGetConversionStatus(IntPtr hIMC, out int lpConversion, out int lpSentence);

        [DllImport("imm32.dll")]
        private static extern bool ImmGetOpenStatus(IntPtr hIMC);

        [DllImport("imm32.dll")]
        private static extern IntPtr ImmGetDefaultIMEWnd(IntPtr hwnd);

        [DllImport("user32.dll")]
        private static extern IntPtr GetKeyboardLayout(uint idThread);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, IntPtr lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);

        public static void Run()
        {
            string name = "keydiag-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".log";
            logPath = Path.Combine(Environment.CurrentDirectory, name);
            try
            {
                writer = new StreamWriter(logPath, false, Encoding.UTF8);
            }
            catch
            {
                logPath = Path.Combine(Path.GetTempPath(), name);
                writer = new StreamWriter(logPath, false, Encoding.UTF8);
            }
            writer.AutoFlush = true;

            try { Console.OutputEncoding = Encoding.UTF8; } catch { }

            Console.WriteLine("KeyDiag log: " + logPath);
            Console.WriteLine("Click the target application, then press keys.");
            Console.WriteLine("Compare a physical keyboard with the HarmonyOS client.");
            Console.WriteLine("Close this window to stop.");

            writer.WriteLine("# KeyDiag " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
            writer.WriteLine("# seq time vk scan state flags shift ctrl alt caps imeOpen imeNative conv fgClass fgTitle focusClass focusTitle");
            writer.WriteLine("# imeNative=1 means the IME is in Chinese/native mode; 0 means English/non-native.");

            hook = SetWindowsHookEx(WH_KEYBOARD_LL, proc, GetModuleHandle(null), 0);
            if (hook == IntPtr.Zero)
            {
                Log("ERROR SetWindowsHookEx failed, win32=" + Marshal.GetLastWin32Error());
                writer.Close();
                return;
            }

            MSG msg;
            while (GetMessage(out msg, IntPtr.Zero, 0, 0) > 0)
            {
                TranslateMessage(ref msg);
                DispatchMessage(ref msg);
            }

            UnhookWindowsHookEx(hook);
            writer.Close();
        }

        private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
        {
            try
            {
                if (nCode >= 0)
                {
                    KBDLLHOOKSTRUCT data = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(KBDLLHOOKSTRUCT));
                    int msg = wParam.ToInt32();
                    bool up = msg == WM_KEYUP || msg == WM_SYSKEYUP;
                    bool sys = msg == WM_SYSKEYDOWN || msg == WM_SYSKEYUP;
                    bool ext = (data.flags & LLKHF_EXTENDED) != 0;
                    bool injected = (data.flags & LLKHF_INJECTED) != 0;

                    IntPtr fg = GetForegroundWindow();
                    IntPtr focus = GetFocusWindow(fg);
                    IntPtr imeWindow = focus != IntPtr.Zero ? focus : fg;

                    int conv = 0;
                    int sent = 0;
                    bool imeOk = false;
                    bool imeOpen = false;
                    IntPtr himc = ImmGetContext(imeWindow);
                    if (himc != IntPtr.Zero)
                    {
                        imeOk = ImmGetConversionStatus(himc, out conv, out sent);
                        imeOpen = ImmGetOpenStatus(himc);
                        ImmReleaseContext(imeWindow, himc);
                    }

                    uint fgPid;
                    uint fgTid = GetWindowThreadProcessId(fg, out fgPid);
                    IntPtr hkl = GetKeyboardLayout(fgTid);
                    int hklId = (int)(hkl.ToInt64() & 0xFFFF);

                    int imeMsg = 0;
                    IntPtr imeWnd = ImmGetDefaultIMEWnd(imeWindow);
                    if (imeWnd != IntPtr.Zero)
                    {
                        UIntPtr msgResult;
                        IntPtr sentOk = SendMessageTimeout(imeWnd, 0x0283, new UIntPtr(1), IntPtr.Zero, 0x0002, 10, out msgResult);
                        if (sentOk != IntPtr.Zero) imeMsg = (int)(msgResult.ToUInt32() & 0xFFFF);
                    }

                    if (!up && data.vkCode == 0x78)
                    {
                        Log("# MARK " + DateTime.Now.ToString("HH:mm:ss.fff") + " --------------------------------------------------");
                    }

                    int shiftState = IsDown(VK_SHIFT) ? 1 : 0;
                    int ctrlState = IsDown(VK_CONTROL) ? 1 : 0;
                    int altState = IsDown(VK_MENU) ? 1 : 0;
                    if (data.vkCode == 0x10 || data.vkCode == 0xA0 || data.vkCode == 0xA1)
                        shiftState = up ? 0 : 1;
                    if (data.vkCode == 0x11 || data.vkCode == 0xA2 || data.vkCode == 0xA3)
                        ctrlState = up ? 0 : 1;
                    if (data.vkCode == 0x12 || data.vkCode == 0xA4 || data.vkCode == 0xA5)
                        altState = up ? 0 : 1;

                    string line = string.Format(
                        "{0,6} {1} vk=0x{2:X2}({3}) scan=0x{4:X2} {5}{6}{7} shift={8} ctrl={9} alt={10} caps={11} imeOpen={12} imeNative={13} conv=0x{14:X4} fg=[{15}] {16} focus=[{17}] {18}",
                        ++seq,
                        DateTime.Now.ToString("HH:mm:ss.fff"),
                        data.vkCode,
                        VkName(data.vkCode, data.scanCode),
                        data.scanCode,
                        up ? "UP" : "DOWN",
                        sys ? " SYS" : "",
                        ext ? " EXT" : "",
                        shiftState,
                        ctrlState,
                        altState,
                        IsToggled(VK_CAPITAL) ? 1 : 0,
                        imeOpen ? 1 : 0,
                        (imeOk && (conv & IME_CMODE_NATIVE) != 0) ? 1 : 0,
                        conv,
                        ClassName(fg),
                        Title(fg),
                        ClassName(focus),
                        Title(focus));

                    line += " imeOk=" + (imeOk ? "1" : "0");
                    line += " hkl=0x" + hklId.ToString("X4");
                    line += " imeMsg=0x" + imeMsg.ToString("X4");
                    line += " rawFlags=0x" + data.flags.ToString("X2");
                    if (injected) line += " INJECTED";
                    Log(line);
                }
            }
            catch (Exception ex)
            {
                Log("ERROR " + ex.Message);
            }
            return CallNextHookEx(hook, nCode, wParam, lParam);
        }

        private static IntPtr GetFocusWindow(IntPtr fg)
        {
            if (fg == IntPtr.Zero) return IntPtr.Zero;
            uint pid;
            uint tid = GetWindowThreadProcessId(fg, out pid);
            GUITHREADINFO gti = new GUITHREADINFO();
            gti.cbSize = (uint)Marshal.SizeOf(typeof(GUITHREADINFO));
            if (GetGUIThreadInfo(tid, ref gti)) return gti.hwndFocus;
            return IntPtr.Zero;
        }

        private static bool IsDown(int vk)
        {
            return (GetAsyncKeyState(vk) & 0x8000) != 0;
        }

        private static bool IsToggled(int vk)
        {
            return (GetKeyState(vk) & 1) != 0;
        }

        private static string VkName(uint vk, uint scan)
        {
            if (vk == 0xE7) return "PACKET(U+" + scan.ToString("X4") + ")";
            if (vk >= 0x41 && vk <= 0x5A) return ((char)vk).ToString();
            if (vk >= 0x30 && vk <= 0x39) return ((char)vk).ToString();
            switch (vk)
            {
                case 0x10: return "SHIFT";
                case 0x11: return "CTRL";
                case 0x12: return "ALT";
                case 0x14: return "CAPS";
                case 0x20: return "SPACE";
                case 0x0D: return "ENTER";
                case 0x09: return "TAB";
                case 0x1B: return "ESC";
                case 0x08: return "BACKSPACE";
                case 0x2E: return "DELETE";
                case 0x25: return "LEFT";
                case 0x26: return "UP";
                case 0x27: return "RIGHT";
                case 0x28: return "DOWN";
                case 0x5B: return "LWIN";
                case 0x5C: return "RWIN";
                default: return "VK_0x" + vk.ToString("X2");
            }
        }

        private static string Title(IntPtr hwnd)
        {
            if (hwnd == IntPtr.Zero) return "";
            StringBuilder sb = new StringBuilder(512);
            GetWindowText(hwnd, sb, sb.Capacity);
            return Clean(sb.ToString());
        }

        private static string ClassName(IntPtr hwnd)
        {
            if (hwnd == IntPtr.Zero) return "";
            StringBuilder sb = new StringBuilder(256);
            GetClassName(hwnd, sb, sb.Capacity);
            return Clean(sb.ToString());
        }

        private static string Clean(string s)
        {
            if (s == null) return "";
            return s.Replace('\r', ' ').Replace('\n', ' ').Replace('|', '/').Trim();
        }

        private static void Log(string line)
        {
            lock (sync)
            {
                try { Console.WriteLine(line); } catch { }
                try { writer.WriteLine(line); } catch { }
            }
        }
    }
}
'@

Add-Type -TypeDefinition $source -Language CSharp
[KeyDiag.Program]::Run()
