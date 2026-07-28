---
description: Pick the single next action and do it
---

Read `docs/efootball/PROGRESS.md`, then confirm its claims against the machine (governor,
`gamemoded -s`, `hyprctl monitors`, platform profile, presence of the proton log).

Choose the **one** highest-value next action and say why it is next. Then do only that one, using
the corresponding `/efb-taskN` procedure and its runbook section.

Ordering rules:
- Anything unverified from an earlier task outranks starting a new one.
- Tasks 1, 2 and 4 share a rebuild — if two of them are edited but not rebuilt, the next action is
  the rebuild, not another edit.
- No measurement is meaningful until `/efb-verify` is green.
- The network work (CGNAT/STUN, bufferbloat, the TCP relay toggle) comes after all four tasks are
  verified. Do not start it early.

Stop after that one action and report. Do not chain into the next task.
