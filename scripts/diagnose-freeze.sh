#!/bin/bash
# 卡死时收集诊断信息：进程采样、CPU、日志尾部。
#
# 用法（远程画面卡住、还没强退时执行）：
#   ./scripts/diagnose-freeze.sh
#
# 结果写到 build/freeze-<时间戳>/，把整个目录发回即可。

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$ROOT/build/freeze-$STAMP"
mkdir -p "$OUT"

echo "==> 输出目录：$OUT"

CLIENT_PID="$(pgrep -f "LanRDP.app/Contents/MacOS/sdl-freerdp" | head -1 || true)"
APP_PID="$(pgrep -x LanRDP | head -1 || true)"

for pair in "app:$APP_PID" "client:$CLIENT_PID"; do
    name="${pair%%:*}"
    pid="${pair##*:}"
    if [[ -z "$pid" ]]; then
        echo "==> 没有找到 $name 进程"
        continue
    fi
    echo "==> 采样 $name ($pid) 5 秒…"
    ps -o pid,ppid,pcpu,pmem,etime,stat,command -p "$pid" >"$OUT/$name-ps.txt" 2>&1
    /usr/bin/sample "$pid" 5 -file "$OUT/$name-sample.txt" >/dev/null 2>&1 \
        || echo "sample 失败（可能需要权限）" >>"$OUT/$name-sample.txt"
    # 线程级调用栈，sample 之外再补一份
    /usr/bin/sample "$pid" 1 -mayDie -file "$OUT/$name-sample-1s.txt" >/dev/null 2>&1 || true
done

if [[ -n "$CLIENT_PID" ]]; then
    echo "==> 客户端参数"
    ps -o command= -p "$CLIENT_PID" >"$OUT/client-command.txt" 2>&1
fi

echo "==> 收集最近日志"
LOG_DIR="$HOME/Library/Application Support/LanRDP/Logs"
if [[ -d "$LOG_DIR" ]]; then
    LATEST="$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1 || true)"
    if [[ -n "$LATEST" ]]; then
        cp "$LATEST" "$OUT/session.log"
        tail -200 "$LATEST" >"$OUT/session-tail.log"
    fi
fi

echo "==> 系统信息"
sw_vers >"$OUT/system.txt" 2>&1
sysctl -n machdep.cpu.brand_string >>"$OUT/system.txt" 2>&1
echo "---- 内存压力 ----" >>"$OUT/system.txt"
memory_pressure 2>/dev/null | tail -5 >>"$OUT/system.txt" 2>&1

echo "==> 完成：$OUT"
ls -lh "$OUT"
