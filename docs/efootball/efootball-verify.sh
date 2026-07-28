#!/usr/bin/env bash
# efootball-verify.sh — run this WHILE A MATCH IS LIVE (second terminal).
# Confirms the four changes actually took effect. Read-only.

set -u
have() { command -v "$1" >/dev/null 2>&1; }
ok()   { printf '  \033[32mOK\033[0m    %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; }
info() { printf '  ..    %s\n' "$*"; }

printf '\n--- 1. CPU governor ---\n'
gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unknown)
[ "$gov" = "performance" ] && ok "governor = performance" || bad "governor = $gov (gamemode did not take)"

printf '\n--- 2. GameMode ---\n'
if have gamemoded; then
  st=$(gamemoded -s 2>&1)
  case "$st" in
    *active*) ok "$st" ;;
    *)        bad "$st" ;;
  esac
else
  bad "gamemoded not on PATH"
fi
if [ -f "$HOME/steam-1665460.log" ]; then
  if grep -q 'gamemodeauto: dlopen failed' "$HOME/steam-1665460.log" 2>/dev/null; then
    bad "proton log still shows 'gamemodeauto: dlopen failed' - libgamemode.so not visible inside the Steam FHS"
  else
    ok "no dlopen failure in the proton log"
  fi
fi

printf '\n--- 3. Proton logging ---\n'
if [ -f "$HOME/steam-1665460.log" ]; then
  sz=$(du -h "$HOME/steam-1665460.log" | cut -f1)
  mt=$(date -r "$HOME/steam-1665460.log" '+%H:%M:%S')
  bad "steam-1665460.log exists ($sz, last written $mt) - PROTON_LOG is still on"
else
  ok "no proton log being written"
fi
ls -1 "$HOME/mangologs"/*.csv >/dev/null 2>&1 && ok "mangohud logs present in ~/mangologs" || info "no mangohud CSV yet (press the logging key at kickoff)"

printf '\n--- 4. Platform profile / GPU state ---\n'
if [ -r /sys/firmware/acpi/platform_profile ]; then
  pp=$(cat /sys/firmware/acpi/platform_profile)
  [ "$pp" = "performance" ] && ok "platform_profile = $pp" || bad "platform_profile = $pp"
else
  info "no /sys/firmware/acpi/platform_profile (legion module not loaded)"
fi
have nvidia-smi && nvidia-smi --query-gpu=pstate,clocks.sm,power.draw,temperature.gpu,utilization.gpu \
  --format=csv,noheader | sed 's/^/  gpu:  /'

printf '\n--- 5. Display / compositor path ---\n'
if have hyprctl; then
  if have jq; then
    hyprctl monitors -j | jq -r '.[] | "  \(.name)  \(.width)x\(.height)@\(.refreshRate|floor)Hz  vrr=\(.vrr)  tearing=\(.activelyTearing)  solitary=\(.solitary)"'
  else
    hyprctl monitors | grep -E '^Monitor|^\s+[0-9]+x[0-9]+@|vrr:|activelyTearing:|solitary:|directScanoutTo:' | sed 's/^/  /'
  fi
  printf '\n  blockers (empty is good):\n'
  hyprctl monitors | grep -E 'tearingBlockedBy|directScanoutBlockedBy|solitaryBlockedBy' | sed 's/^/  /'
fi

printf '\n--- 6. What the game is actually talking to ---\n'
if have ss; then
  ss -unpH 2>/dev/null | grep -iE 'efootball|wine|proton' | awk '{print "  peer: " $6}' | sort -u | head
fi
printf '\n'
