# Implementation Tracker

Status values: `TODO`, `IN PROGRESS`, `BLOCKED`, `DONE`, `REJECTED`, `N/A`.

Last updated 2026-09-17, after the inventory (`01-current-state.md`) and the bake-off
(`06-decisions.md`).

> **Read this first:** much of what the original template listed as work to do already existed in
> this repo before the ricing project started. Rows marked `DONE (pre-existing)` are recorded so a
> future agent does not rebuild them.

## Foundation

| Task | Status | Notes |
|---|---|---|
| inventory current repo | DONE | `01-current-state.md`, written from repo + live system |
| document ownership conflicts | DONE | 58 verified findings; the ricing-relevant ones are in `01-current-state.md` |
| identify Hyprland pin/source | DONE | nixpkgs 25.11 → **0.52.2**; hyprpaper is the only desktop package from unstable |
| identify Home Manager boundaries | DONE | HM-as-NixOS-module, `useGlobalPkgs`; `hyprEnabled` gate keeps `wm/` off the VM |
| preserve recovery terminal shortcut | DONE (pre-existing) | `$mod+Return`; Alacritty is installed at *system* level so it survives a failed HM activation |
| establish the channel-bump plan | DONE | Scoped and written up as `docs/2605-bump-runbook.md`. 26.05 ships Hyprland 0.55.4, kernel 6.18.52, NVIDIA 595.71.05 |
| execute the 26.05 bump | DONE | Step 0 confirmed by the user (10 entries seen in the firmware menu), then bumped. Hyprland 0.55.4, kernel 6.18.52, NVIDIA 595.71.05 |
| validate the 26.05 generation | DONE | Gen 209 booted. Zero failed units, all 10 desktop units up, both monitors native, LazyVim intact, GSP `N/A`. Runtime items (suspend/resume, gaming) still need real use |
| adopt systemd stage 1 | TODO | Pinned `false` during the bump so it is one variable, not two. Deprecated; removal scheduled for 26.11 |

## Shell

| Task | Status | Notes |
|---|---|---|
| evaluate Caelestia | DONE | Rejected — owns notifications with no opt-out; settings GUI fights HM on every login (#1426) |
| evaluate DMS | DONE | Best Nix story of the three; blocked by 25.11 (no package, no module) + Lua-only compositor docs |
| evaluate Noctalia | DONE | v5 dropped Qt entirely; blocked by 25.11 + `settings.toml` loads last and cannot be disabled |
| consider custom Quickshell | DONE | Rejected — 3–6 months to parity; quickshell #723 (NVIDIA FD leak) and #1098 (dual-monitor reload SIGSEGV) |
| choose one shell | DONE | **ADR-004** — keep waybar + walker/elephant + mako + swayosd |
| re-evaluate after 26.05 | TODO | **Now unblocked.** But note 26.05 has quickshell **0.3.0** and the shells want ≥0.3.1, and `caelestia-shell` is still unstable-only |

## Theme / palette

| Task | Status | Notes |
|---|---|---|
| palette: off-palette surfaces named | DONE | `bgDeep` #16161e and `scrim` #101018 — walker's popup surface is **not** `bg`, which was undocumented. Pure white/black washes deliberately left literal as material effects |
| define design tokens | DONE | `home/dani/theme/palette.nix` — 26 tiered roles + views for all four syntaxes. `theme/default.nix` is a build-time gate: WCAG AAA for `text`, 3:1 for `dim`, cyan-band check. Negative-tested both ways |
| evaluate Matugen | DONE | Rejected as authority — Nix module is build-time + IFD, drops hooks, `exit 0` on read-only. 26.05 now ships **4.0.0**, so the Tier-2 option in ADR-005 is available if wanted |
| evaluate Stylix | DONE | Rejected — `release-25.11` frozen since 2026-04-29; no `mkDefault`; silent CSS concat on waybar |
| choose theme authority | DONE | **ADR-005** — Tier 1 Nix tokens (frozen), Tier 2 ambient optional/later |
| palette reachable from both layers | DONE | `theme/palette.nix` at the repo root, passed via `specialArgs` + `extraSpecialArgs`. Needed for SDDM: the system layer must not relative-import out of `home/dani/` |
| migrate ~200 literals onto tokens | DONE | **All of them.** ~250 literals across 20 files and six syntaxes. Every `#hex` left in the repo is now in `theme/palette.nix`; the only other survivors are walker's pure white/black alpha washes, left literal on purpose as material effects. Every consumer proven byte-identical |
| generate `waybar/palette.css` from tokens | DONE | Verified byte-identical to the installed file — pure refactor |
| optional Tier-2 ambient via matugen | TODO | Only after Tier 1 lands; capped at 3–4 meaning-free roles |

## Wallpaper

| Task | Status | Notes |
|---|---|---|
| inventory current wallpaper stack | DONE | hyprpaper 0.8.4 (unstable) + walker contact-sheet picker |
| evaluate swww | DONE | Renamed **awww**; measured 2.6 MiB RSS vs hyprpaper's 123 MiB on this machine |
| choose backend | DONE | **ADR-006** — migrate to awww, hand-written unit |
| migrate `wall-set` to `awww img -t fade` | DONE | `d35d88c`. Changing wallpaper no longer restarts a service, so the black flash on every change is gone. Memory: RSS 122.4 → 2.8 MiB (~45×) but cgroup only 97.6 → ~57–70 MiB (~1.5×), because awww's wl_shm buffers are charged to the cgroup and not to RSS — always state which metric |
| re-apply on HDMI-A-1 re-dock | DONE | `00d1bf2`, glob fixed in `2c011ca`. Calls the shared `wall-apply`, not `awww restore` — same store path as the unit's `ExecStartPost`, so the two cannot drift. The original `monitoradded*HDMI-A-1*` matched `monitoraddedv2` too and ran the whole body twice per connect. Needs a physical replug to confirm |
| store-backed fallback wallpaper | DONE | `d35d88c`, reachability fixed in `197f02d`, import narrowed in `8aa1303`. A read-only store path that rolls back with the generation, reached on *failure to apply* rather than only on a missing file — the original `[ ! -f ]` guard meant an undecodable file took the other branch, so the fallback was unreachable in exactly the case it existed for. Since `815db77` it is the greeter's own anchor (5120×2880, downscales) rather than `default.png` (#1C8ED9, 1920×1200, upscaled) |
| `awww restore` / daemon cache | REJECTED, but the stated reason was wrong | `197f02d`. The daemon **does** restore on start — it forks `sh -c` to run its own `awww` client from PATH, and the probe that concluded otherwise ran under a `systemd-run` PATH with no awww in it (`exec: awww: not found`, twice per start, in the journal). It therefore raced `ExecStartPost` and won at t=0.2 s. Still rejected — `awww restore` exits 0 having restored nothing, and the cache is version-keyed — but now enforced with `--no-cache` rather than assumed |
| unify the greeter and the desktop fallback | DONE | `815db77`. They pinned *different* images, so the no-selection state was the worst-looking one. Now one value in `theme/scene.nix`, shared via `specialArgs`. Greeter derivation bit-identical |
| make the greeter follow the picker | **REJECTED** | **ADR-014.** Possible (session-pushed handoff outside `$HOME`; fully designed and verified) but not worth its permanent machinery for a few seconds of screen time, on a machine whose greeter is one of two recovery paths. Reopen if the stale login image ever actually annoys |

## Hyprland visuals

| Task | Status | Notes |
|---|---|---|
| centralize gaps/radii/borders | TODO | Folds into the token layer |
| border value ramp (A/B) | IN PROGRESS | `rgba(737aa2ff) rgba(3b4261ff) 45deg` — one hue, two values. The 2026-07-22 revert killed a *hue* gradient; this is the opposite. Live toggle in the scratchpad, awaiting a verdict |
| Alacritty opacity double-dip | DONE | `fba9c22`. 0.96 × Hyprland 0.94/0.88 put the terminal at 0.902/0.845 while every other window was 0.94/0.88 — a value-signal drift |
| lock-screen escape hatch | DONE | `003117e`. Zero locked binds existed, so a crashed hyprlock was a hard power cycle. `allow_session_lock_restore` + a `bindld` |
| asymmetric animations | DONE | `846cbe6`. Root cause was the *curve*, not the duration: easeOutQuint is an arrival curve, and on an exit it spent ~137 ms creeping the last 3%. windowsOut/layersOut → `linear`, fadeSwitch split off `fade`. Cheaper too — all three are AVARDAMAGE_ENTIRE |
| `rounding_power` squircles | DONE | `fc14b5d`. Shipped as `rounding = 16` + `rounding_power = 4.0` — one change, not two. r16/p4 clips ~18.7 px² per corner vs r12/p2's 30.9 px², so a softer corner that eats *fewer* app pixels |
| `vibrancy_darkness` + blur tuning | REJECTED | All three judges rejected touching blur. size 3 / passes 1 is already correct and documented; every proposed change (passes 2, brightness 0.93, vibrancy 0.10) moves away from "the wallpaper stays recognisable", which is the point of the glass |
| layer blur / `xray` on shell layers | BLOCKED | Reliability judge: waybar's is a **verified no-op** that still forces a full-monitor pre-blur; walker's prerequisite is unverified. Do not add until `hyprctl layers` has been checked with each surface actually open |
| `misc:vrr = 2` | TODO | Fullscreen-only is correct for laptop + external |
| app-specific rules | DONE (pre-existing) | Media viewers at full opacity; portal choosers floated |
| special workspaces | DONE (pre-existing) | 12-tile scratchpad board on `$mod+S` |
| gaming rules | TODO | `programs.gamemode.settings` is `{}` — no hook point exists yet |
| glow | REJECTED (unanimous) | Available on 0.55.4, and all three judges — including the one briefed to push for boldness — rejected it. Renders at `DECORATION_LAYER_OVER` i.e. **on top of app pixels**; there is **no `glow`/`no_glow` window rule** so nothing can be exempted; active-only colour re-introduces "hue = focus", which the 2026-07-22 A/B rejected; defaults are cyan `#33ccff` |
| Hyprland plugins | REJECTED | ADR-010 — official repo gutted 2026-05-12; hyprexpo/hyprtrails/hyprwinwrap gone |
| Hyprland rule-grammar migration | DONE | Landed with the bump; gated by `check-all`'s `--verify-config` pass |
| **Lua config migration** | BLOCKED | Not forced — hyprlang still parses on 0.55.4, and `configType` stays `hyprlang` while `home.stateVersion = "25.05"`. Note `hyprctl keyword` is hyprlang-only, so the effect-profile design is coupled to staying |

## Services / apps

| Task | Status | Notes |
|---|---|---|
| hyprlock | DONE (pre-existing) | **But:** `grace` + `disable_loading_bar` are dead keys — see Defects |
| hypridle | DONE (pre-existing) | No idle auto-lock by choice; staged listeners are an available upgrade |
| hyprsunset | DONE (pre-existing) | Measured 203 ms CPU in 4.6 h — the 0.3.3 busy-loop does not reproduce here |
| hyprpolkitagent | REJECTED (for now) | ADR-013 — nixpkgs pinned at Qt/QML 0.1.3; upstream rewrote to hyprtoolkit in 0.2.0 |
| hyprshutdown | BLOCKED | ADR-013 — absent from 25.11; v0.1.1 migrated dispatchers to Hyprland 0.55+ Lua |
| Hyprcursor | REJECTED | ADR-013 — inert at scale 1.0; nixpkgs bibata is `-p x11` only; upstream quiet since 2025-07-31 |
| Ghostty | REJECTED | ADR-012 — PR #14052 puts NVIDIA on a CPU copy path; revisit after 1.4.0 |
| Yazi | DONE (pre-existing) | Consider unstable (25.11 freezes it at 25.5.31) + `withGraphics` for real image previews |
| Firefox | TODO | Two builds in the closure; the *system default* is the policy-free one |
| Neovim | TODO | Same bug: yazi and file managers launch the unwrapped build |
| GTK/Qt | TODO | **dconf owns the font** — see Defects |

## Interaction

| Task | Status | Notes |
|---|---|---|
| launcher/command palette | DONE (pre-existing) | walker + elephant, 4 themes, 2 local patches — **ADR-007** keep |
| pin walker/elephant by rev | TODO | Currently unpinned moving branches; `nix flake update` can move them arbitrarily |
| re-verify `pwcopy` after any walker bump | TODO | walker #738 is open with no maintainer reply; same code-path family |
| notifications | DONE (pre-existing) | mako — but the unit has no restart trigger and two start paths |
| OSD | DONE (pre-existing) | swayosd, styled to match the bar |
| control center | TODO | The one surface a narrow Quickshell instance could justify, post-26.05 |
| clipboard history | DONE (pre-existing) | elephant provider, 12 h TTL, plaintext `.gob` |
| media surface | DONE (pre-existing) | waybar `mpris` |
| system HUD | TODO | |
| screenshots | DONE (pre-existing) | grim+slurp+satty — missing freeze, window and output subjects |
| recording | TODO | ADR-012 — `gpu-screen-recorder` for the instant-replay wishlist item |

## Login / boot

| Task | Status | Notes |
|---|---|---|
| inventory greeter | DONE | SDDM + sddm-astronaut, **X11 greeter deliberately** |
| choose/style greeter | DONE | **ADR-008** — keep SDDM |
| align Plymouth | TODO | Where the low-risk boot-visual polish actually is |
| visual transition audit | TODO | Plymouth → greeter handoff; `plymouth quit --retain-splash` |
| bootloader experiment | BLOCKED | ADR-001 — only after desktop completion |

## Defects found during inventory (prerequisites)

These are not ricing; they are the reason ricing would half-apply if layered on top.

| Task | Severity | Status | Notes |
|---|---|---|---|
| hyprlock dead config keys | high | DONE | Removed; `--grace 2` moved to the bind, not to hypridle's suspend path |
| dconf owns the GTK font | high | DONE | Inter installed, `defaultFonts` pinned, dconf keys declared |
| waybar renders on the bottom layer | — | ACCEPTED | Decision 2026-09-17: keep it. `mode = "dock"` overrides `layer = "top"`; a bottom-layer bar keeps fullscreen games/video edge-to-edge. Cost documented in `wm/mouseless.nix` and `wm/waybar.nix`: escape #1 is unavailable while anything is fullscreen |
| ~~mako has no `X-Restart-Triggers`~~ | — | REJECTED | Withdrawn: HM fires `makoctl reload` onChange (verified live). A restart trigger would be *worse* — it drops queued notifications |
| mako unit hardcodes `pkgs.mako` | low | TODO | Should be `config.services.mako.package`; same store path today, so latent |
| mako has two start paths | low | TODO | D-Bus activation resurrects it outside the cgroup — only bites when deliberately stopped |
| Firefox: unwrapped build is the default handler | high | DONE | Both handlers now use `finalPackage` |
| waybar `custom/kblayout` 1 s poll | medium | TODO | ADR-011 — ~90 % of waybar's CPU is forked scripts |
| HM portal set shadows the system set | high | TODO | System `extraPortals` is mostly dead weight |
| `AQ_DRM_DEVICES` hardcoded to `card1` | high | DONE | Gated on `videoDrivers` containing nvidia; verified absent on danix-hp. Open: it may be a pure multi-GPU workaround and this box is single-GPU — needs a deliberate test |
| `flatpak-remotes.service` permanently failed | high | DONE | Orders after `nss-lookup.target`, retries 5×, exits 0 on the soft path |
| `wall-apply` dead code | low | DONE | Deleted |
| dead `unstablePkgs` binding | low | DONE | Deleted |
| elephant menu rescan race | medium | DEFERRED | Correct fix depends on HM activation ordering internals that the 26.05 bump changes. Revisit on HM 26.05 rather than fixing against a module about to move |
| `hypr-dock-handler` `Restart=on-failure` | medium | DONE | Now `always` + `RestartSec=2` |
| boot menu offers 3 generations | medium | DONE | Raised to 10, matching what `rescue-blackscreen.md` already promised. /boot has 940 MB free; a generation costs ~47 MB |
| stale docs (waytrogen, theme count, Plymouth) | low | TODO | Listed in `01-current-state.md` |

## Profiles

| Profile | Status | Notes |
|---|---|---|
| daily | BLOCKED | ADR-009 — profile machinery deferred to post-Lua |
| cinematic | BLOCKED | " |
| showcase | BLOCKED | " — `borderangle loop` and mpvpaper belong here and nowhere else |
| gaming | BLOCKED | " — needs a `programs.gamemode.settings` hook, which does not exist yet |
| battery | BLOCKED | " |
| reduced-motion | BLOCKED | " |

## Final audit

| Task | Status | Notes |
|---|---|---|
| resource benchmark | DONE (baseline) | 93.9 % idle CPU, 3.9 GiB RAM, 26 % GPU / 837 MiB VRAM, ~463 MB shell RSS |
| shell-crash recovery | DONE (verified) | All nine user units are independently restartable; no `BindsTo` |
| suspend/resume | TODO | |
| monitor hotplug | TODO | `hypr-dock-handler` exists; the `sleep 1` race is untested |
| gaming validation | TODO | |
| rollback validation | TODO | |
| acceptance checklist | TODO | `09-acceptance-checklist.md` |
