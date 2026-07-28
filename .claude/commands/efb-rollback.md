---
description: Undo one task, or everything
argument-hint: "[1|2|3|4|all]"
---

Undo scope: `$ARGUMENTS`

Read "Phase 7 — Rollback" in `docs/efootball/efootball-execution-runbook.md`.

- For a single task: find its commit with `git log --oneline -10`, show it to me, and propose
  `git revert <sha>`. Do not revert until I approve the sha.
- For `all`: the fastest route is `sudo nixos-rebuild switch --rollback` back to generation 151.
  Print it for me to run; do not run it.
- Task 3 involves no Nix at all — it is the Steam launch options string, which I have to paste
  back myself. The previous value is recorded in `docs/efootball/PROGRESS.md`.
- Task 4 can be undone immediately without a rebuild:
  `echo balanced | sudo tee /sys/firmware/acpi/platform_profile`

Update `docs/efootball/PROGRESS.md` to mark the task `reverted`, and record why in the session log
— a revert that is not explained is a revert we will repeat.
