---
description: Analyse the MangoHud frametime logs and tell me what they mean
argument-hint: "[offline|online|both]"
---

Run `python3 docs/efootball/frametime-report.py ~/mangologs/*.csv`.

Then:
- Compare against the expected medians: ~13.3ms at 75Hz, ~6.1ms at 165Hz, ~16.7ms means something
  is still capping at 60.
- Say which of these the numbers point at: render path, thermal throttling, shader compilation,
  CPU contention, or nothing local (i.e. network).
- If I have both an offline and an online capture, compare them directly. Similar frametimes but a
  worse *feel* online means netcode/transport, and no local setting will fix it.
- Append a row to the Measurements table in `docs/efootball/PROGRESS.md`.

Be honest if the numbers show no improvement. Do not narrate a win that is not in the data.
