#!/usr/bin/env bash
# efootball-triage.sh — collect the facts needed to tune eFootball/Proton on NixOS.
#
# READ-ONLY. It changes nothing, needs no root, and touches no game files.
# Usage:  bash efootball-triage.sh [outfile]
# Fish users: just `bash efootball-triage.sh` — do not try to source it.

set -u
export LC_ALL=C
APPID=1665460
OUT="${1:-./efootball-triage-$(date +%Y%m%d-%H%M).txt}"
FINDINGS=()

have()  { command -v "$1" >/dev/null 2>&1; }
sec()   { printf '\n\n===== %s =====\n' "$*"; }
r()     { printf '\n$ %s\n' "$1"; eval "$1" 2>&1 | sed 's/^/  /'; }
note()  { printf '  -> %s\n' "$*"; }
flag()  { FINDINGS+=("$*"); }

{
printf 'efootball-triage  %s\n' "$(date -Is)"

# ---------------------------------------------------------------- host
sec "HOST / GENERATION"
r "hostname"
have nixos-version && r "nixos-version"
r "uname -srm"
r "uptime -p"
if [ -e /run/booted-system ] && [ -e /run/current-system ]; then
  booted=$(readlink -f /run/booted-system)
  current=$(readlink -f /run/current-system)
  printf '\n  booted-system : %s\n  current-system: %s\n' "$booted" "$current"
  if [ "$booted" != "$current" ]; then
    note "MISMATCH — you have rebuilt since booting."
    flag "REBOOT NEEDED: booted-system != current-system. If the rebuild touched the kernel or GPU driver, expect exactly the once-per-session crash pattern, and nothing in the game log will explain it."
  else
    note "match — running system is the booted one."
  fi
  r "ls -1t /nix/var/nix/profiles/ 2>/dev/null | head -3"
else
  printf '\n  /run/booted-system absent — not a NixOS host, comparison skipped.\n'
fi

# ---------------------------------------------------------------- cpu / ram
sec "CPU / MEMORY"
r "lscpu | grep -E 'Model name|^CPU\\(s\\)|Thread|Core\\(s\\)|MHz|Vulnerab.*mitigation' | head -12"
gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unknown)
printf '\n  cpu governor: %s\n' "$gov"
[ "$gov" = "powersave" ] && flag "CPU governor is 'powersave'. gamemode should flip this to performance during play — verify it actually does."
r "free -h"
r "swapon --show"
have zramctl && r "zramctl"
if [ -z "$(swapon --show --noheadings 2>/dev/null)" ]; then
  flag "No swap or zram configured. Under memory pressure systemd-oomd kills the biggest cgroup, which is the game."
fi

# ---------------------------------------------------------------- gpu
sec "GPU"
have lspci && r "lspci -nn | grep -Ei 'vga|3d|display'"
gpucount=$(lspci 2>/dev/null | grep -Eic 'vga|3d' || echo 0)
[ "$gpucount" -gt 1 ] && flag "More than one GPU present (hybrid graphics). Confirm in MangoHud that the dGPU is the one rendering — the iGPU rendering by accident feels exactly like 'sluggish players'."
if have nvidia-smi; then
  r "nvidia-smi --query-gpu=name,driver_version,pstate,power.limit,temperature.gpu,clocks.sm --format=csv"
  r "nvidia-smi -q -d PERFORMANCE | grep -A6 'Clocks Event Reasons' | head -12"
fi
have vulkaninfo && r "vulkaninfo --summary 2>/dev/null | grep -A4 'GPU[0-9]' | head -40"
have glxinfo && r "glxinfo -B 2>/dev/null | grep -E 'OpenGL renderer|OpenGL version' "

# ---------------------------------------------------------------- display / compositor
sec "DISPLAY / COMPOSITOR"
printf '\n  XDG_SESSION_TYPE=%s  XDG_CURRENT_DESKTOP=%s\n' "${XDG_SESSION_TYPE:-unset}" "${XDG_CURRENT_DESKTOP:-unset}"
if have hyprctl; then
  r "hyprctl version | head -3"
  r "hyprctl monitors"
  for opt in general:allow_tearing misc:vrr misc:vfr decoration:blur:enabled animations:enabled render:direct_scanout; do
    r "hyprctl getoption $opt | head -2"
  done
  r "hyprctl clients | grep -iA3 football"
fi

# ---------------------------------------------------------------- kernel knobs
sec "KERNEL TUNABLES"
for k in vm.max_map_count vm.swappiness net.core.default_qdisc net.ipv4.tcp_congestion_control net.core.rmem_max; do
  printf '  %-34s %s\n' "$k" "$(sysctl -n $k 2>/dev/null || echo '?')"
done
mmc=$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)
[ "$mmc" -lt 1048576 ] 2>/dev/null && flag "vm.max_map_count is $mmc. Unreal+DXVK can exhaust the default; classic symptom is a hang or crash partway into a session."

# ---------------------------------------------------------------- crash evidence
sec "CRASH EVIDENCE (this boot)"
r "journalctl -k -b --no-pager | grep -iE 'xid|gpu has fallen|nvrm|amdgpu.*(reset|timeout)|oom-kill|Out of memory|segfault|traps:' | tail -40"
r "systemctl is-active systemd-oomd"
r "journalctl -b --no-pager -u systemd-oomd | tail -15"
have coredumpctl && r "coredumpctl list --since '-7 days' --no-pager 2>/dev/null | tail -15"
for lg in "$HOME/steam-$APPID.log" "$HOME/steam-*.log"; do
  [ -e "$lg" ] && r "ls -la $lg && tail -40 $lg"
done

# ---------------------------------------------------------------- steam / proton
sec "STEAM / PROTON / TOOLING"
for b in steam gamemoderun mangohud gamescope nft mtr; do
  printf '  %-14s %s\n' "$b" "$(command -v $b || echo 'NOT FOUND')"
done
have gamemoded && r "gamemoded -s"
for base in "$HOME/.steam/steam" "$HOME/.local/share/Steam"; do
  [ -d "$base" ] || continue
  r "ls -1 $base/compatibilitytools.d/ 2>/dev/null"
  r "ls -1d $base/steamapps/common/Proton* 2>/dev/null"
  r "grep -A6 '\"$APPID\"' $base/config/config.vdf 2>/dev/null | head -20"
  r "grep -rhoE '\"LaunchOptions\"[[:space:]]+\"[^\"]*\"' $base/userdata/*/config/localconfig.vdf 2>/dev/null | sort -u | head"
  r "find $base -maxdepth 4 -name 'appmanifest_$APPID.acf' -exec grep -E '\"name\"|\"buildid\"' {} + 2>/dev/null"
done
r "ls -la $HOME/.cache/nvidia/GLCache 2>/dev/null | tail -3; du -sh $HOME/.cache/nvidia 2>/dev/null"

# ---------------------------------------------------------------- network link
sec "NETWORK — LINK"
r "ip -br -4 addr"
r "ip route get 1.1.1.1"
defdev=$(ip route 2>/dev/null | awk '/^default/{print $5; exit}')
gw=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')
printf '\n  default device: %s   gateway: %s\n' "${defdev:-?}" "${gw:-?}"
if [ -n "${defdev:-}" ]; then
  r "cat /sys/class/net/$defdev/speed 2>/dev/null; cat /sys/class/net/$defdev/mtu"
  case "$defdev" in
    wl*) flag "Default route is over Wi-Fi ($defdev). Wi-Fi jitter alone can account for the 'half a beat late' feeling in a P2P match."
         have iw && r "iw dev $defdev link"
         have iw && r "iw dev $defdev get power_save"
         ;;
    tailscale*|tun*) flag "Default route is via $defdev — game traffic may be tunnelled. Check for an active exit node." ;;
  esac
fi
have nmcli && r "nmcli -t -f DEVICE,TYPE,STATE device | grep -v unmanaged"
r "tc qdisc show | head -20"
tc qdisc show 2>/dev/null | grep -qE 'cake|fq_codel' || flag "No cake/fq_codel qdisc on the egress interface — nothing is managing latency under load locally."

# ---------------------------------------------------------------- nat / path
sec "NETWORK — PATH & NAT"
pub=$(curl -4 -s --max-time 6 https://ifconfig.me 2>/dev/null)
printf '\n  public IPv4 (masked): %s\n' "$(printf '%s' "${pub:-unknown}" | sed -E 's/^([0-9]+\.[0-9]+)\..*/\1.x.x/')"
r "ip -br -4 addr show scope global | grep -vE 'tailscale|docker|virbr|podman'"
if have traceroute; then
  r "traceroute -n -w 1 -q 1 -m 6 1.1.1.1"
  path=$(traceroute -n -w 1 -q 1 -m 6 1.1.1.1 2>/dev/null)
elif have mtr; then
  r "mtr -n -r -c 3 -m 6 1.1.1.1"
  path=$(mtr -n -r -c 3 -m 6 1.1.1.1 2>/dev/null)
else
  path=""
fi
if printf '%s' "$path" | grep -qE '(^|[^0-9])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.'; then
  flag "A 100.64/10 address appears on the path to the internet — that is the CGNAT range. If it is NOT your tailscale0 hop, you are behind carrier-grade NAT, P2P hole punching fails, and you get relayed into the slow transport every match. This is the single highest-impact thing on the list."
fi
if [ -n "${gw:-}" ]; then
  r "ping -c 20 -i 0.2 -n $gw | tail -3"
fi
r "ping -c 20 -i 0.2 -n 1.1.1.1 | tail -3"

# ---------------------------------------------------------------- tailscale / timers
sec "TAILSCALE & SCHEDULED JOBS"
if have tailscale; then
  r "tailscale status --peers=false 2>/dev/null | head -5"
  r "tailscale status --json 2>/dev/null | grep -iE 'ExitNode|Online\"' | head -5"
fi
r "systemctl list-timers --all --no-pager | head -20"
r "systemctl --user list-timers --all --no-pager 2>/dev/null | head -15"

# ---------------------------------------------------------------- verdict
sec "AUTOMATED FINDINGS"
if [ ${#FINDINGS[@]} -eq 0 ]; then
  printf '\n  Nothing obviously wrong at the system level. The problem is more likely\n'
  printf '  in-game settings, the compositor path, or the far end of the connection.\n'
else
  i=1
  for f in "${FINDINGS[@]}"; do
    printf '\n  [%d] %s\n' "$i" "$f"
    i=$((i+1))
  done
fi
printf '\n\n(end)\n'
} > "$OUT" 2>&1

printf 'Written to: %s\n\n' "$OUT"
grep -A200 'AUTOMATED FINDINGS' "$OUT"
