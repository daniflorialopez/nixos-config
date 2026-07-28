# eFootball performance work — progress

Claude Code updates this file as tasks complete. It is the memory that survives
between sessions, so read it first and write to it last.

## Status

| # | Task | State | Verified by | Notes |
|---|------|-------|-------------|-------|
| 1 | Refresh rate 60 → 75 / 165 | verified | `hyprctl monitors` | 288001e; gen 152, HDMI@74.999 + eDP@165.003 persisted after rebuild |
| 2 | GameMode engages (libgamemode.so in FHS) | verified | `gamemoded -s` | a6a59bb; active + governor performance on all 20 threads; libgamemode.so.0 in /usr/lib AND /usr/lib32. Residual dlopen-fail lines are startup-phase, outside game FHS; clean-log recheck deferred to task 3. Hooks deferred (task 4). |
| 3 | Drop PROTON_LOG, new launch options | verified | no `~/steam-1665460.log` | 3.4/3.5/3.6 all green: no proton log written, CSVs land in ~/mangologs via F2. Frametime report works. |
| 4 | Platform profile → performance | BLOCKED, deferred | sysfs write | doubly blocked: (a) TLP on, ppd disabled (tlp.nix:5) so no `powerprofilesctl`; (b) `/sys/firmware/acpi/platform_profile` absent — needs out-of-tree lenovo-legion-module + reboot. User chose to defer. Runbook says other 3 stand alone. |

States: `not started` / `edited, not rebuilt` / `applied, unverified` / `verified` / `reverted`

## Baseline (before any change)

- generation at start: 151
- both displays: 2560x1440 @ 60
- governor during play: powersave  → now performance (task 2, gen 152)
- `gamemoded -s`: inactive  → now active (task 2, gen 152)
- proton log: 9.2 MB of `trace:seh:`
- frametime median: not yet measured

## Launch options (task 3)

Active string (MSI panel; frame cap via MangoHud `fps_limit=75` — DXVK_FRAME_RATE alone did NOT cap, likely D3D12/vkd3d), no PROTON_LOG:

```
SDL_VIDEODRIVER=x11 __GL_MaxFramesAllowed=1 __GL_SHADER_DISK_CACHE_SIZE=12000000000 __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1 DXVK_FRAME_RATE=75 MANGOHUD_CONFIG=fps,frame_timing=1,gpu_name,gpu_stats,gpu_temp,cpu_stats,cpu_temp,vram,ram,fps_limit=75,output_folder=/home/dani/mangologs,log_duration=180,toggle_logging=F2 gamemoderun mangohud %command%
```

Crash-hunting variant — same string with PROTON_LOG=1 prepended (re-enable only when chasing a crash; it recreates ~/steam-1665460.log):

```
PROTON_LOG=1 SDL_VIDEODRIVER=x11 __GL_MaxFramesAllowed=1 __GL_SHADER_DISK_CACHE_SIZE=12000000000 __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1 DXVK_FRAME_RATE=75 MANGOHUD_CONFIG=fps,frame_timing=1,gpu_name,gpu_stats,gpu_temp,cpu_stats,cpu_temp,vram,ram,fps_limit=75,output_folder=/home/dani/mangologs,log_duration=180,toggle_logging=F2 gamemoderun mangohud %command%
```

Prior string (for reference, replaced): `PROTON_LOG=1 SDL_VIDEODRIVER=x11 MANGOHUD_CONFIG=fps,frame_timing=1,gpu_name,gpu_stats,gpu_temp,cpu_stats,cpu_temp,vram,ram,vulkan_driver gamemoderun mangohud %command%` — note the old MANGOHUD_CONFIG had no output_folder/toggle_logging, hence no CSVs.

## Measurements

| Date | Scenario | Median ft | 1% low | stdev | Feel 1-5 | Notes |
|------|----------|-----------|--------|-------|----------|-------|
| 2026-07-28 | match, 160s (gen 152, tasks 1-3) | 6.10 ms | 19.84 ms (50 fps) | 3.18 ms | — | UNCAPPED: fps med 165 / max 420 — DXVK_FRAME_RATE=75 ignored (likely D3D12/vkd3d). GPU 99% load but clock stuck ~1110MHz / 88W. cpu_temp 97C, gpu_temp 87C. 1% low is the real issue. |
| 2026-07-28 | match, 180s (+ MangoHud fps_limit=75) | 13.33 ms | 13.59 ms (74 fps) | 0.31 ms | — | CAP WORKS. Locked 75 fps, near-perfect pacing (stdev 0.31ms, hitches 0.01%). GPU 74C/38% load (unpinned, boosts to 1786MHz when needed), cpu 80C. Report verdict: local render path clean → remaining lateness is network. Task 4 further deprioritized (GPU healthy). |

## Session log

<!-- newest first; one line per session -->
- 2026-07-28: Cutscene/menu GPU spikes (100% load, 87C) reviewed and INTENTIONALLY LEFT AS-IS. They're brief, thermally safe (87C = throttle onset, not damage), and don't touch gameplay pacing. In-game frame-rate options are only 60/120 (no 75), which is why we cap via MangoHud fps_limit=75. IMPORTANT: keep in-game frame rate at 120/Unlimited — setting it to 60 would cap gameplay at 60 and undo the 75. Optional future fix if fan noise annoys: nvidia-smi power/clock cap (latency-free, reversible) — not applied.
- 2026-07-28: Frame cap FIXED via MangoHud fps_limit=75. Re-measured: median 13.33ms (locked 75fps), 1% low 13.59ms, stdev 0.31ms (was 3.18), hitches 0.01% (was 7.22%). Temps down ~13-17C. Local render path now clean per report verdict. All 3 unblocked tasks done + validated. REMAINING: Task 4 (deferred, now clearly low value — GPU healthy) and the network work (CGNAT/STUN, bufferbloat, TCP relay) which is the likely source of any felt lateness. No git changes (launch options live in Steam, not repo).
- 2026-07-28: Task 3 VERIFIED (no proton log, CSVs land via F2). First measured session — median ft 6.10ms but UNCAPPED (fps 165 median/420 max): DXVK_FRAME_RATE=75 not limiting, likely eFootball on D3D12/vkd3d where that env var doesn't apply. Also GPU clock-limited (~1110MHz @ 99% load, 88W) = concrete evidence for deferred Task 4. Next candidate action (beyond the 4 tasks): make the cap work — MangoHud fps_limit=75 (cross-API) or in-game cap — then re-measure. Task 4 (GPU TGP) now has data backing it.
- 2026-07-28: Task 3 applied — new launch options pasted + saved (localconfig.vdf confirms new string, no PROTON_LOG; 3.4 green). Old MANGOHUD_CONFIG lacked output_folder/toggle_logging → explains zero CSVs historically; new one has output_folder=/home/dani/mangologs + toggle_logging=F2 + log_duration=180. Stale ~/steam-1665460.log (1.9M) left for user to rm. Pending a play session: 3.5 (no new log) + 3.6 (CSV via F2). Crash-hunting variant saved above.
- 2026-07-28: /efb-verify ran live (match active, GPU 99% util/85W/88C). GREEN: governor=performance, gamemode active, displays 75/165. RED: (1) proton log dlopen-fail grep — false positive, stale startup lines; (2) proton log exists = task 3 pending. Platform_profile absent (task 4 deferred). Both REDs collapse to task 3 (remove PROTON_LOG + delete stale log). No mangohud CSV yet (F2 at kickoff). Next: /efb-task3.
- 2026-07-28: REBUILT (gen 152, user). Tasks 1+2 VERIFIED — monitors 75/165 persisted; gamemode active + governor performance on all threads; libgamemode.so in /usr/lib + /usr/lib32. Next action: Task 3 (drop PROTON_LOG, install measuring launch options) — manual Steam UI. Then /efb-verify live, then measure. Task 4 still deferred (blocked).
- 2026-07-28: Task 2 committed a6a59bb — Steam extraPackages [gamemode mangohud] (the dlopen/FHS fix). Hooks omitted. Task 4 found BLOCKED: TLP+ppd conflict AND missing platform_profile interface; user deferred it.
- 2026-07-28: Task 1 persisted — hyprland.nix monitor modes 60→75/165, committed 288001e. Not rebuilt (shares rebuild with tasks 2+4). Correction: config used explicit @60, not `preferred`. testUFO frame-skip check PASSED (user, normal results). Runbook 1.10 resolution/fullscreen items are MOOT for eFootball: game has no in-game resolution or display-mode menu; settings.dat is an encrypted blob (magic `btfe`). Game inherits desktop res = 2560x1440 (already correct) and already runs `fullscreen: 2` at 2560x1440@75 on HDMI-A-1 (verified via hyprctl while running). Only V-Sync/frame-rate items in-game remain (set V-Sync Off, framerate Unlimited). Direct scanout is a separate marginal opt: blocked by `render:direct_scanout` off (user settings) AND by non-solitary workspace; enabling render:direct_scanout live cleared the user-settings blocker but solitary still blocked by other windows/layers on the output. Not persisted — deferred, low priority vs tasks 2/4. Next: `/efb-task2`.
- 2026-07-28: verified baseline (gen 151, both 60Hz, gamemode inactive, proton log present). Task 1 live test passed — HDMI-A-1@75, eDP-1@165 accepted, no black screen. Not persisted.
