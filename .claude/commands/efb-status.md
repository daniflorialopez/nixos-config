---
description: Where the eFootball performance work stands right now
---

Read `docs/efootball/PROGRESS.md` first.

Then gather current state read-only. Do not change anything, do not use sudo:

- `hyprctl monitors | grep -E '^Monitor|2560x1440@'`
- `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor`
- `gamemoded -s` (if present)
- `cat /sys/firmware/acpi/platform_profile` (if it exists)
- `ls -la ~/steam-1665460.log` (its absence is the goal)
- `ls -1 ~/mangologs/*.csv 2>/dev/null | tail -3`
- `git -C . log --oneline -5` and `git status --short`

Then report, in a short table: each of the four tasks, whether the evidence says it is applied,
and what the next single action is. Where the evidence contradicts PROGRESS.md, say so and correct
the file. Do not start any task — this command only reports.
