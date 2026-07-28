# eFootball performance work — progress

Claude Code updates this file as tasks complete. It is the memory that survives
between sessions, so read it first and write to it last.

## Status

| # | Task | State | Verified by | Notes |
|---|------|-------|-------------|-------|
| 1 | Refresh rate 60 → 75 / 165 | not started | `hyprctl monitors` | |
| 2 | GameMode engages (libgamemode.so in FHS) | not started | `gamemoded -s` | |
| 3 | Drop PROTON_LOG, new launch options | not started | no `~/steam-1665460.log` | manual, Steam UI |
| 4 | Platform profile → performance | not started | `powerprofilesctl get` | |

States: `not started` / `edited, not rebuilt` / `applied, unverified` / `verified` / `reverted`

## Baseline (before any change)

- generation at start: 151
- both displays: 2560x1440 @ 60
- governor during play: powersave
- `gamemoded -s`: inactive
- proton log: 9.2 MB of `trace:seh:`
- frametime median: not yet measured

## Measurements

| Date | Scenario | Median ft | 1% low | stdev | Feel 1-5 | Notes |
|------|----------|-----------|--------|-------|----------|-------|

## Session log

<!-- newest first; one line per session -->
