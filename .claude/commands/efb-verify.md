---
description: Run the verification script during a live match and interpret it
---

Run `bash docs/efootball/efootball-verify.sh` and interpret the output.

For every FAIL, map it to the runbook section that fixes it, using the table in
"Phase 5 — Verification pass" of `docs/efootball/efootball-execution-runbook.md`. Give me one
next action, not a list of six.

If the script reports the game is not running, say so first — the checks are only meaningful
during a live match.

Then update the status table in `docs/efootball/PROGRESS.md` to match what the script actually
found, and append a dated line to the session log.
