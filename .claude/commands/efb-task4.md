---
description: Task 4 — platform profile to performance during play
---

Task 4 of `docs/efootball/efootball-execution-runbook.md`. Read section "Task 4" first.

1. Check the interface exists:
   `cat /sys/firmware/acpi/platform_profile_choices` and `cat /sys/firmware/acpi/platform_profile`
2. If it does not exist, do **not** silently add the out-of-tree Lenovo module. Explain the
   tradeoff from runbook step 4.2 (it can fail to build on a future kernel bump) and let me decide
   between the module, the BIOS/`Fn+Q` route, and skipping the task.
3. If it exists: print the by-hand test command for me to run (`echo performance | sudo tee …`) —
   do not run it yourself — plus the `nvidia-smi` watch command for checking pstate under load.
4. Persistence is the GameMode hook from task 2, so check whether task 2 landed first. If it did
   not, say so and stop.
5. Confirm `services.power-profiles-daemon.enable = true;` is set, and that TLP is not.

Note for me at the end: performance mode usually only unlocks fully on AC, and the fans get loud.

Update `docs/efootball/PROGRESS.md`.
