---
description: Task 2 — make GameMode actually engage (libgamemode.so inside the Steam FHS)
---

Task 2 of `docs/efootball/efootball-execution-runbook.md`. Read section "Task 2" first.

The bug, from the user's Proton log:
`gamemodeauto: dlopen failed - libgamemode.so: cannot open shared object file`

`gamemoderun` preloads `libgamemodeauto.so` successfully, but its dlopen of `libgamemode.so` fails
inside Steam's FHS sandbox, so the request never reaches the daemon and the CPU governor stays on
powersave during matches.

Do this:

1. `rg -n 'programs.steam' .` and `rg -n -A6 'programs.gamemode' .` — show me what exists now.
2. Propose a unified diff that adds `extraPackages = with pkgs; [ gamemode mangohud ];` to
   `programs.steam`, and the `custom.start` / `custom.end` GameMode hooks from the runbook
   (which also cover task 4). Preserve every existing attribute.
3. Check the module header has `pkgs` in scope; if not, fix it in the same diff.
4. Check whether `services.power-profiles-daemon` is enabled and whether TLP is present
   (`rg -n 'tlp' .`) — they conflict. Tell me which situation applies before I rebuild.
5. Commit with the message from the runbook. Do **not** rebuild, do **not** use sudo.

Then print, as a checklist for me: the rebuild command, the "fully exit Steam" step and why it
matters, and the two verification commands.

Update `docs/efootball/PROGRESS.md`.
