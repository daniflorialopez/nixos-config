---
description: Task 1 — drive both displays at 75Hz / 165Hz instead of 60Hz
argument-hint: "[live|persist]"
---

Task 1 of `docs/efootball/efootball-execution-runbook.md`. Read section "Task 1 — Refresh rate"
in that file before doing anything, and follow it exactly.

Context: `HDMI-A-1` (MSI MP273QP) runs 59.951Hz but supports 75.00. `eDP-1` runs 60.000 but
supports 165.00. The cause is almost certainly `preferred` in the monitor config, which takes the
EDID preferred mode.

Argument `$ARGUMENTS`:
- `live` (or empty) → do step 1.1–1.4 only: the `hyprctl keyword` live test and verification.
  Stop there and report. Nothing is written to disk.
- `persist` → do steps 1.5–1.7: find the monitor config with `rg`, show me a unified diff of the
  proposed edit, apply it after I approve, and commit. Do **not** rebuild.

Rules:
- Change the mode field only. Leave position and scale exactly as they are.
- Before editing, show me what `rg -n 'monitor' home/` actually found, so I can confirm you are
  editing the right file.
- If a screen goes black during the live test, immediately print the blind-recovery command from
  runbook step 1.3.
- In-game settings (step 1.10) are mine to do. List them for me and wait.

Update `docs/efootball/PROGRESS.md` when done.
