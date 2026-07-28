---
description: Task 3 — drop PROTON_LOG and install the measuring launch options
---

Task 3 of `docs/efootball/efootball-execution-runbook.md`. Read section "Task 3" first.

This one is mostly mine to do, because Steam's launch options live in its GUI. Your job is to
prepare and verify.

1. `mkdir -p ~/mangologs` (no sudo needed).
2. Show me the current saved launch options:
   `rg -o '"LaunchOptions".*' ~/.local/share/Steam/userdata/*/config/localconfig.vdf`
   (Steam writes that file on exit, so warn me if Steam is running — `pgrep -a steam`.)
3. Print the replacement string from the runbook in a copyable block, with `DXVK_FRAME_RATE` set
   for whichever panel I say I play on (75 for the MSI, 162 for the laptop). Ask me which if I
   have not said.
4. Tell me the exact click path in Steam, then wait for me to confirm I have pasted it.
5. After I confirm: `ls -la ~/steam-1665460.log` and tell me to delete it if it is still there.
6. After my next session: check `~/mangologs` for a CSV. If none, give me the two fallbacks
   (`toggle_logging=Shift_L+F2`, or `autostart_log=10`).

Save the crash-hunting variant (same string with `PROTON_LOG=1` prepended) as a comment in
`docs/efootball/PROGRESS.md` so it is not lost.
