#!/usr/bin/env bash
# eFootball FREEZE capture — run THE INSTANT the game freezes, BEFORE force-quitting.
#
# If the whole desktop is frozen, get a shell one of two ways:
#   - SSH in from your phone/another machine over Tailscale, or
#   - switch to a text VT with Ctrl+Alt+F3, log in, run this, Ctrl+Alt+F1 back.
#
# Everything here is read-only and needs no sudo. Output is teed to a file.
set -u
out="$HOME/efootball-freeze-$(date +%Y%m%d-%H%M%S).txt"
exec > >(tee "$out") 2>&1
echo "### eFootball freeze capture — $(date)"

echo; echo "== GPU: load / clocks / power / temp =="
nvidia-smi --query-gpu=utilization.gpu,utilization.memory,clocks.sm,clocks.mem,power.draw,power.limit,temperature.gpu,memory.used,memory.total --format=csv 2>&1
echo "-- throttle reasons (thermal/power/reliability = a stuck GPU) --"
nvidia-smi -q -d PERFORMANCE 2>&1 | sed -n '/Clocks Event Reasons/,/^ *$/p'

echo; echo "== game process state (R=spinning  D=blocked on IO/GPU  S=waiting) =="
pids=$(pgrep -f 'eFootball.exe' | tr '\n' ' ')
echo "pids: ${pids:-NONE FOUND}"
for p in $pids; do
  read -r _ _ st _ < /proc/"$p"/stat 2>/dev/null
  echo "  pid $p  state=$st  wchan=$(cat /proc/"$p"/wchan 2>/dev/null)"
done

echo; echo "== hottest threads (is anything actually running?) =="
top -H -b -n1 2>/dev/null | grep -iE 'PID|eFootball|wine|d3d|nvidia' | head -25

echo; echo "== any process stuck in D-state (uninterruptible = driver/IO deadlock) =="
ps -eLo pid,tid,stat,wchan:28,comm | awk 'NR==1 || $3 ~ /D/'

echo; echo "== kernel msgs, last 3 min (Xid / hung task / OOM) =="
journalctl -k --since "-3min" --no-pager 2>&1 | grep -iE 'xid|nvrm|hung task|blocked for more than|oom|gpu has fallen' | tail -20

echo; echo "== game/steam/proton journal, last 3 min =="
journalctl --since "-3min" --no-pager 2>&1 | grep -iE 'efootball|proton|wine|steam|gamemode|vkd3d|dxvk' | tail -20

echo; echo "== memory =="; free -h
echo; echo ">>> saved to: $out"
