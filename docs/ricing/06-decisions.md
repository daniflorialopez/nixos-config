# Architectural Decision Log

Record decisions that change ownership or architecture. Do not record trivial styling tweaks.

## ADR template

### ADR-NNN — Title

**Status:** proposed / accepted / superseded / rejected
**Date:** YYYY-MM-DD

#### Context

What problem are we solving?

#### Options considered

- option A
- option B
- option C

#### Decision

What are we choosing?

#### Why

Why this option?

#### Ownership impact

What component now owns what?

#### Risks

What could go wrong?

#### Rollback

How can this be reversed?

---

## Existing decisions

### ADR-001 — Keep systemd-boot during desktop redesign

**Status:** accepted

Keep systemd-boot while the desktop is redesigned. Bootloader experiments, if any, happen later on a separate branch.

### ADR-002 — One owner per desktop responsibility

**Status:** accepted

Each responsibility and generated configuration file has one declared primary owner to avoid Home Manager/runtime-generator conflicts.

---

## Bake-off decisions, 2026-09-17

All ADRs below were made after a verified upstream survey (12 research passes + 3 adversarial
fact-checking passes, all sources fetched 2026-09-17) cross-referenced against the inventory in
`01-current-state.md`. Version claims were checked against this repo's own `flake.lock` revisions,
not against channel heads.

### ADR-003 — The nixpkgs 25.11 pin is the binding constraint on this project

**Status:** accepted → **RESOLVED 2026-09-17** by the bump to `nixos-26.05`
**Date:** 2026-09-17

> **Resolution.** The bump was executed the same day. See `docs/2605-bump-runbook.md`
> for the full scope and risk register. What it delivered against the table below:
> Hyprland 0.52.2 → **0.55.4**, Qt 6.10.2 → **6.11.1**, quickshell 0.2.1 → **0.3.0**,
> matugen 3.0.0 → **4.0.0**, vicinae 0.16.11 → **0.23.2**, hyprshutdown and `wayle` now
> present, hypridle/hyprsunset unchanged. Kernel 6.12.93 → 6.18.52 and NVIDIA 580.142 →
> 595.71.05 came with it.
>
> Two of the deferrals below are now **unblocked and should be re-evaluated**: the
> Quickshell shells (ADR-004) and Matugen-as-Tier-2 (ADR-005). Two are **not**:
> `caelestia-shell` is still absent from 26.05 (it is unstable-only), and quickshell is
> 0.3.0 where the shells want ≥0.3.1.
>
> One deferral changed shape rather than lifting: ADR-009 deferred the effect-profile
> system to "after the Lua migration". That migration is **not forced** — hyprlang still
> parses on 0.55.4, and `configType` is pinned to `hyprlang` explicitly. Note that
> `hyprctl keyword` is hyprlang-only from 0.55, so the profile mechanism is now coupled
> to *staying* on hyprlang rather than to leaving it.

#### Context

Nearly every "modern Hyprland rice" component evaluated turned out to be blocked by the channel
pin rather than by the hardware or the architecture. Measured against `flake.lock` rev `b6018f8`:

| Component | 25.11 has | needed / current upstream |
|---|---|---|
| Hyprland | 0.52.2 | 0.56.2 — **Lua config since 0.55** |
| Qt base | 6.10.2 | 6.12 carries the fix for QTBUG-95817 |
| quickshell | 0.2.1 (2025-10) | 0.3.1 — shells require ≥0.3.0 |
| caelestia-shell | **absent** | 2.4.0 in unstable |
| noctalia | **absent** | 5.1.0 in unstable |
| dms-shell + `programs.dms-shell` | **absent** | present in unstable, first-party |
| matugen | 3.0.0 | 4.2.0 — template syntax incompatible |
| vicinae | 0.16.11 | 0.28.2 |
| hyprsunset | 0.3.3 | 0.4.0 — 0.3.3 predates a 100 %-CPU busy-loop fix |
| hypridle | 0.1.7 | 0.1.8 — no `condition_cmd` on 0.1.7 |
| hyprshutdown | **absent** | 0.1.1 |

#### Decision

Treat the channel bump to 26.05 as a **first-class project milestone**, not a side effect. Until
then, prefer improvements that are native to 0.52.2 and that do not need a second nixpkgs tree in
the closure. Where a package genuinely must be newer, use the existing `unstablePkgs` pattern
(precedent: hyprpaper) rather than adding new flake inputs.

#### Why

An earlier reading of the evidence attributed several blockers to the NVIDIA proprietary driver.
The adversarial pass overturned that: QTBUG-95817 — the bug behind the "Qt refuses the threaded
render loop on NVIDIA, so QML shells are capped near 60 fps" claim — is **Closed/Fixed, fixVersion
6.12.0** (Qt 6.12 released 2026-05-29). It was never a Qt policy or a driver limitation; it was a
resize defect whose workaround (frameworks reporting `ThreadedOpenGL` unsupported) produced the
observable ceiling. The blocker is therefore a *stale pin with a known expiry*, not a property of
this machine.

A second correction matters here: **legionix is discrete-only.** `/sys/class/drm/` holds one card,
bound to `nvidia`; neither `i915` nor `xe` is loaded. A large share of the NVIDIA bug reports in
the survey (caelestia #1845/#1797, DMS #3304/#3438/#3447, quickshell #679) are from *hybrid*
machines and describe iGPU↔dGPU switching or PRIME offload. Those mechanisms do not exist here and
must not be weighted as "my exact hardware".

#### Ownership impact

None directly. This ADR sets the deferral gate that ADR-004, ADR-009 and ADR-010 reference.

#### Risks

Deferring means running a compositor four minors behind, including two releases of the hyprlang
grace period (ADR-009). Security-relevant components are unaffected — the pin is a desktop
constraint, not a base-system one.

#### Rollback

Not applicable; this is a scheduling decision.

---

### ADR-004 — Keep the current shell stack; do not adopt a Quickshell shell yet

**Status:** accepted
**Date:** 2026-09-17

#### Context

Bake-off between Caelestia, DankMaterialShell, Noctalia, a custom Quickshell shell, and the
existing waybar + walker/elephant + mako + swayosd stack.

#### Options considered

- **Caelestia** — 12.4k★, ~20 commits in six days, **three breaking config commits in one week**.
  Owns the notification daemon with **no `enabled` key** (`notifsconfig.hpp` has no such property),
  so it is a hard conflict with mako. Its settings GUI rewrites `shell.json` at runtime; issue
  #1426 reports `Read-only file system` on NixOS *on every login*. Packaged in nixos-unstable
  (2.4.0) but absent from 25.11.
- **DankMaterialShell** — the most complete option and the best Nix story: first-party
  `programs.dms-shell` *in nixpkgs* with proper `mkRemovedOptionModule` migrations, declarative
  plugins with a lockfile, a `stable` branch, `nixosTests`. ~4.6 commits/day. But its compositor
  docs are **Lua-only** (assume Hyprland ≥0.55), `quickshell.package` carries **no version
  assertion** so a 0.2.1 mismatch fails at runtime rather than at eval, and it collapses nine
  daemons into one QML process **that is also the lock screen**.
- **Noctalia** — v5 is a ground-up C++/OpenGL-ES rewrite; Quickshell is gone. Well-formed flake,
  build-time `noctalia config validate`, a built-in `Tokyo-Night` palette. But `~/.local/state/noctalia/settings.toml`
  **loads last and wins**, with no documented way to disable it — the HM module seeds defaults and
  cannot be made authoritative. Absent from 25.11 entirely.
- **Custom Quickshell** — realistic solo effort to parity is 3–6 months of evenings, and the
  launcher alone argues against it.
- **Status quo.**

#### Decision

**Keep waybar + walker/elephant + mako + swayosd.** Re-evaluate DankMaterialShell and Noctalia
after the 26.05 bump (ADR-003). If a Quickshell surface is ever added, add it as a *second-class
citizen for one thing waybar architecturally cannot do* — a control centre or an overview — never
as the bar, the launcher or the lock screen.

#### Why

Three disqualifiers, in order of weight:

1. **Quickshell issue #723** (open since 2026-04-10, two comments): Quickshell leaks DRM
   `sync_file` FDs on **NVIDIA proprietary + Hyprland** until it hits the 1024 soft limit and the
   Wayland connection dies — reproducibly after 2–4 days of uptime. Cross-filed from noctalia#2274,
   where the Noctalia devs confirmed the QML was correct and the leak is below the shell layer.
   That is this exact hardware and compositor, it kills the process rather than degrading, and it
   is not a hybrid-GPU report.
2. **Quickshell issue #1098** (2026-09-08, a 0.3.1 *current-release* regression): SIGSEGV in
   `QWindow::setScreen` on config reload and on SIGTERM **whenever a second output is connected** —
   "19 of my 25 crash reports are this one frame". This machine is permanently dual-monitor, and
   the bug specifically destroys hot reload, which is Quickshell's headline feature.
3. **Single-process blast radius.** Under DMS or Noctalia, one process is the bar, launcher,
   notification daemon, OSD, wallpaper *and* the `ext-session-lock-v1` client. When it dies while
   locked, the protocol requires the compositor to keep the session locked with no client — and
   the recovery is "escape via VT", which **does not exist on this machine** (`01-current-state.md`,
   recovery gaps). Today waybar, walker, mako and hyprlock are four independent processes with
   independent restart policies; a crashing bar cannot take the lock screen with it.

The current stack costs ~463 MB RSS and 0 % idle CPU outside waybar's own polling (which ADR-011
fixes). It does not crash. Nothing in the field is a superset of it.

#### Ownership impact

Unchanged: waybar owns the bar, walker/elephant own the command plane, mako owns notifications,
swayosd owns the OSD, hyprlock owns the lock screen.

#### Risks

The stack ages. Walker has had zero commits for two months (see ADR-006). Revisit annually.

#### Rollback

Not applicable — this is a decision not to change.

---

### ADR-005 — Two-tier palette: Nix owns semantics, nothing owns them at runtime

**Status:** accepted
**Date:** 2026-09-17

#### Context

`docs/design-system.md` encodes four rules that no colour generator models: blue is the accent and
orange is attention-only; the sunset gradient means load; **no cyan**, because Dani cannot reliably
distinguish it from blue/white; and contrast is calibrated to **WCAG AAA (≥7:1 on `#1a1b26`)**.
Meanwhile ~200 hardcoded literals live across ~15 files in four incompatible syntaxes, with
`waybar/palette.css` as the only named-role definition and exactly one consumer.

#### Options considered

- **Stylix** — 100 targets, ~20 of which overlap this stack.
- **Matugen** as runtime authority.
- **Shell-native / base16** discipline.
- **A hand-written Nix token layer.**

#### Decision

Build a **Tier 1** token layer in Nix — one `palette.nix` exporting named roles plus derived views
(`hex`, `noHash`, `rgba`, `ansi16`), consumed by every module that currently hardcodes hex, with
**build-time assertions** that enforce the design rules. Treat Matugen as an optional, strictly
contained **Tier 2** ambient generator, adopted later or never.

The firewall between tiers is the **file boundary**, and it is mechanical:

```
TIER 1 — semantic, frozen      /nix/store (read-only)   Nix/HM owns it
TIER 2 — ambient, derived      ~/.local/state/theme/    Nix never declares the path
```

Tier 2 is capped at 3–4 meaning-free roles (a wash, a lock backdrop, a gap fill). **Never** in
Tier 2: accent, attention, critical, warning, success, muted, fg, bg, or any border that signals
focus. Every consumer must render correctly if the Tier-2 file is missing or stale.

#### Why

**Against Stylix:** on `release-25.11` its last behavioural change was **2026-04-29** — the branch
is in maintenance-by-neglect. Its hyprpaper target still emits the pre-0.8 flat config format
(fixed on master via #2122, never backported) and has **no per-monitor support at all**, which is a
functional regression against `wall-set`. Critically, `mk-target.nix` emits target config at
**normal priority with no `mkDefault`** (only 3 of 100 modules use it), so every hand-written
colour becomes either a hard eval conflict or — for `programs.waybar.style`, whose type is
`lines` — a **silent stylesheet concatenation**, where Stylix's block landing above ours invalidates
`@import "palette.css"` and every role reference falls back with no error. And there is no `sddm`
or `walker` target, so a hand-written colour layer survives regardless: full adoption still yields
a hybrid.

**Against Matugen as authority:** its Nix module is **build-time, not runtime** — it runs matugen
inside `runCommandLocal` at rebuild time on a store-copied wallpaper, so changing the wallpaper at
runtime does nothing. It is also **Import From Derivation**, which serialises evaluation behind a
build and breaks `nix flake check` under restricted eval. It silently drops `pre_hook`/`post_hook`
(declared as options but never emitted into the TOML — verified against `main`). And at runtime,
when it hits a read-only output path it logs one line and `return Ok(())` — **exit code 0** — so a
wrapper checking `$status` reports success while the theme never updates.

**Against wallpaper-derived semantics, categorically:** no generator in either tool computes a
contrast ratio. Matugen's `contrast` knob is a −1..1 global lightness bias, not a WCAG target. A
sunset wallpaper makes `accent` orange and destroys rule #1; a teal-heavy wallpaper pushes `accent`
into the cyan band and attacks rule #3 — the *accessibility* constraint, not a taste one.

**For the token layer:** the competitive advantage is that a Nix layer can **enforce** the rules.
A build-time assertion that computes WCAG contrast against `bg` and fails the build when a
text-tier role falls under 7:1 — or when a role's hue lands in the cyan band — is a guarantee
neither Stylix nor Matugen can offer. And the seam Matugen would need already exists in this repo,
twice: `@import "palette.css"` from an HM-owned stylesheet, and `source = ~/.local/state/hypr/hyprpaper-selected.conf`
from an HM-owned config.

#### Ownership impact

`home/dani/theme/palette.nix` becomes the single source for every colour in the repo.
`waybar/palette.css` is generated from it rather than being the definition. If Tier 2 is ever
adopted, matugen owns `~/.local/state/theme/` and nothing else.

#### Risks

Nobody upstream fixes our contrast assertion when nixpkgs bumps waybar's CSS classes or hyprpaper's
config grammar. Every ecosystem breaking change is ours. Accepted: the design constraints are
non-negotiable and no engine models them.

#### Rollback

The token layer is a pure refactor — values are unchanged, only their source moves. Revert the
commit and the literals come back.

---

### ADR-006 — Migrate the wallpaper backend from hyprpaper to awww

**Status:** accepted
**Date:** 2026-09-17

#### Context

hyprpaper 0.8.4 is the current backend. `wall-set` changes wallpaper by rewriting a sourced config
file and **restarting the service**, which black-flashes both outputs.

#### Decision

Migrate to **awww** (the renamed, still-maintained `swww` — repo archived under the old name
2025-10-31, now at `codeberg.org/LGFae/awww`). **Hand-write the systemd unit**; do not use HM's
`services.swww`.

#### Why

Measured on this machine, 2026-09-17, both 2560×1440 outputs live:

| | hyprpaper 0.8.4 | awww 0.12.1 |
|---|---|---|
| RSS | **125,768 kB** | **2,684 kB** |
| PSS | 73,033 kB | — |
| shm buffers | — | 28.1 MiB (shared with compositor) |
| idle CPU | 0.0 % | 0 ticks / 10 s |
| VRAM | in the EGL path (hyprtoolkit/libglvnd) | **zero** — `wl_shm` CPU buffers only |
| transitions | **none** (verified: zero transition keys registered in `ConfigManager.cpp`) | 14 types, byte-identical between 0.11.2 and 0.12.1 |

That is a ~45× reduction in private resident memory, and awww never enters the EGL path at all —
which on a machine whose entire desktop story is "NVIDIA proprietary + mixed 75/165 Hz" is the most
valuable property available.

The decisive functional finding: **hyprpaper 0.8.4's runtime IPC is broken.** 0.8.0 replaced the
line-oriented text socket with `hyprwire`, a binary protocol, but `hyprctl` still speaks the old
text protocol. Verified live — `hyprctl hyprpaper wallpaper "eDP-1,…"` returns empty with exit 0
while the daemon logs `core protocol error: malformed message recvd (invalid type code)`. hyprpaper
0.8.4 ships exactly one binary and no client. So there is **no supported way to change the
wallpaper at runtime**, and the restart-the-service approach in `wall-set` is not laziness — it is
currently the only thing that works. awww restores this capability and adds the crossfade.

Rejected alternatives: **wpaperd** has the best transitions of anything surveyed (GL-accelerated
gl-transitions, a real `wpaperctl`, a proper HM module) and its README states plainly that
*"Hyprland is not supported by wpaperd"* — an upstream refusal to accept bug reports. **mpvpaper**
is semi-abandoned, nixpkgs is a release behind, its own `--auto-pause`/`--auto-stop` flags carry an
upstream asterisk reading "might not work as intended", and a video wallpaper is a continuously
damaging background surface that defeats VFR entirely. Reserve it for a showcase profile if ever.

#### Ownership impact

awww owns the wallpaper. `wall-set` keeps writing `~/.local/state/wallpaper/current` for the walker
picker, but replaces the config-write + service-restart with a single `awww img -t fade`. The
`hypr-dock-handler` gains one line to re-apply on HDMI-A-1 re-dock.

#### Risks

- HM's `services.swww` on `release-25.11` execs `swww-daemon`, which awww does not ship → 203/EXEC
  (HM #9029). Fixed on master **as a rename**: the module is now `services.awww`, with
  `services.swww.*` surviving only as a warning-emitting alias. Hand-writing the unit sidesteps
  both and keeps the existing `ExecStartPre` / `X-Restart-Triggers` idioms.
- awww emitted `[WARN] We failed to find wayland buffer with id: 11. This should be impossible.`
  twice against Hyprland 0.52.2 during the probe. Cosmetic there — the wallpaper applied correctly
  — but worth a log-watch after adoption.
- Hot-add restore on a live output connect is **unverified**; mitigated by the dock-handler line.
- Upstream is deliberately feature-frozen ("NEW FEATURES WILL NOT BE ADDED, UNLESS THEY ARE
  EGREGIOUSLY SIMPLE"). Fine for a wallpaper daemon.

#### Rollback

Revert the commit. hyprpaper stays in nixpkgs and the state file format is unchanged.

---

### ADR-007 — Keep walker + elephant; pin the input by revision

**Status:** accepted
**Date:** 2026-09-17

#### Context

Walker carries ~1150 lines of configuration, four hand-written GTK4 themes with their own
`layout.xml`/`item_*_grid.xml`, three elephant menus, and **two local patches** against a flake
input that tracks a moving branch with no `ref` or `rev`.

#### Decision

Stay. Additionally: **pin `walker` and `elephant` by explicit revision** in `flake.nix` rather than
drifting on an unpinned default branch, so `nix flake update` cannot move them by accident.

#### Why

Nothing in the field is a superset. Hyprlauncher (hyprtoolkit) has no clipboard and no window
switcher, and its theming is "follows your hyprtoolkit theme" — there is no layout system at all.
fuzzel/rofi/anyrun are list renderers. The shell-native launchers are inseparable from shells that
ADR-004 rejects.

**Vicinae** is the only serious contender and is genuinely better on four axes: Qt instead of the
GTK4/NVIDIA `GSK_RENDERER` trap, optionally AES256-GCM-encrypted clipboard storage (real value
while the disk is unencrypted), five releases in three weeks against walker's two months of
silence, one daemon instead of two, and it would let us delete both downstream patches. It is
rejected because **its theme system is a colour table with no layout dimension whatsoever**. All
four custom themes and all three elephant menus would become either impossible or a
TypeScript/React codebase whose Nix build path is a known-open bug (HM #8262, open since
2025-12-02). "A two-card yes/no prompt sized for two answers instead of a 600×570 board" is simply
not expressible in Vicinae. Also: nixpkgs 25.11 ships **0.16.11** against upstream 0.28.2.

#### Ownership impact

Unchanged.

#### Risks

- Walker's last commit was **2026-07-16**; open issues sit unanswered, including **#738 "Pause
  feature in elephant-clipboard is completely broken"** (2026-08-31, no maintainer reply). Our
  `pwcopy` uses the *CLI* pause path, not the in-UI one, so this is not a confirmed break of the
  secret-copy guarantee — but it is the same code-path family and **must be re-verified by hand
  after any bump**.
- Both patches are a standing upgrade tax. `walker-window-per-theme`'s first hunk is a `use` list
  that rustfmt will reorder the moment upstream touches `crate::ui::window`. Mitigating: patch
  failure aborts `patchPhase`, so this breaks the build loudly rather than regressing at runtime.

#### Rollback

n/a.

---

### ADR-008 — Keep SDDM; invest the greeter budget in Plymouth

**Status:** accepted
**Date:** 2026-09-17

#### Context

SDDM runs an X11 greeter deliberately (`sddm.nix:95`), because weston's kiosk shell stacked every
greeter window on one output and kwin was unstable on the closed NVIDIA driver.

#### Decision

**Keep SDDM.** Do not migrate to greetd. Spend the effort on a custom Plymouth theme and the
boot→greeter handoff instead.

#### Why

ReGreet's own README calls it *"a single-monitor application"*, and the nixpkgs multi-head spanning
issue (#226586) has been open since April 2023. nixpkgs 25.11 pins **0.2.0** (tagged 2025-01-06)
while upstream is at 0.5.0 — the project is *not* abandoned (three releases in 2026; an earlier
claim of "no tag in 26 months" was a year misread and is withdrawn), but the packaged version is
~20 months stale and there is an open SIGTRAP-after-idle crash (#170) in the one process standing
between the user and the machine.

The greetd variant that *does* handle two monitors — Hyprland-as-greeter — reintroduces exactly the
Aquamarine DRM-teardown SIGSEGV that `sddm.nix`'s own comment already documents.

The one genuine SDDM defect, the logout dead console, is **already solved** by
`logout-to-greeter.service` plus its scoped polkit rule.

**Critical coupling, recorded here because it is a one-line footgun:** `services.xserver.enable = true`
at `sddm.nix:80` is commented as a Cinnamon dependency, but it is also what the X11 greeter rides
on. Removing Cinnamon without also reckoning with the greeter removes the only graphical login —
and there is no text console on this machine. **Any Cinnamon-removal change must keep
`services.xserver.enable = true` explicitly, with a comment saying why.**

#### Ownership impact

Unchanged. Plymouth (`boot.plymouth`, currently `bgrt`) becomes the target for boot-visual work.

#### Risks

SDDM has not cut a release since 0.21.0 (2024-02-26), and KDE shipped `plasma-login-manager` in
Plasma 6.6. Note the correction: KDE describes it as *"an optional new login manager for Plasma"*,
not as SDDM's successor, and SDDM's `develop` branch is still receiving commits. The cost is real
but is a 169 MiB permanently-resident X server, not an imminent failure.

#### Rollback

n/a. If revisited, prove the logout loop survives a non-zero Hyprland exit **in the VM host** first.

---

### ADR-009 — Do not build effect-profile machinery on Hyprland 0.52.2

**Status:** accepted
**Date:** 2026-09-17

#### Context

The brief asks for six switchable profiles: `daily`, `cinematic`, `showcase`, `gaming`, `battery`,
`reduced-motion`.

#### Decision

**Defer the profile system.** For now, tune `decoration` and `animations` in place. Build the
profile mechanism after the Lua migration (ADR-003).

#### Why

Hyprland announced on **2026-04-26** that Lua replaces hyprlang from 0.55, with the old syntax
surviving *"1 - 2 releases … after that, hyprlang will be dropped"*. 0.55 and 0.56 have both
shipped — the grace window is spent. Concretely, on a bump:

- `windowrulev2` becomes a **hard parse error** (`res.setError("windowrulev2 is deprecated…")`,
  `ConfigManager.cpp:431` @ v0.56.2).
- The `windowrule` *and* `layerrule* grammars changed shape in 0.53 with no back-compat:
  `windowrule = float, class:^(firefox)$` → `windowrule = match:class ^(firefox)$, float true`.
  **All 11 `windowrulev2` lines and all 9 `layerrule` lines in `hyprland.nix` break.**
- `hyprctl keyword` is **not in the current `using-hyprctl` docs**; the replacement is
  `hyprctl eval 'hl.config({ … })'`.
- `bindd` is safe — the `d` flag survives, alongside a grown flag set.

The best 0.52.2 profile mechanism is an `exec =` line (which re-runs on every reload, unlike
`exec-once`) invoking a generated script that emits one `hyprctl --batch keyword …`. It works, and
it is **throwaway code**: on 0.56+, `hl.config()` is callable directly from a keybind, holding
profile state in Lua with no reload, no IPC and no script. HM master already ships
`configType = "lua"` + `extraLuaFiles`.

Building the scaffolding now means writing it twice.

#### Ownership impact

Hyprland keeps owning compositor behaviour. No new profile owner is introduced yet.

#### Risks

The brief asks for profiles and this defers them. Mitigated by delivering the *visual* gains now
(ADR-010) — which are where the perceptible improvement actually is — and by making the Lua
migration an explicit tracker item.

#### Rollback

n/a.

---

### ADR-010 — Advance the visuals within 0.52.2; no plugins

**Status:** accepted
**Date:** 2026-09-17

#### Context

What visual improvement is available *today*, without a channel bump and without plugins?

#### Decision

Tune in place. Specifically available and verified present in 0.52.2:

- **`rounding_power`** is real (range 2.0–10.0 on 0.52.2; ≈4 is the squircle look) and free — it
  only changes the SDF exponent.
- **Asymmetric animations.** Upstream's own 0.52.2 default opens slow and eased (4.1 dec,
  `easeOutQuint`) and closes fast and linear (1.49 dec). The current config uses the same curve
  both ways, which is why closes feel sluggish.
- **`vibrancy_darkness`** (currently unset, default 0) raises the brightness floor so dark-but-
  saturated colours also get the saturation boost.
- **`blur:xray`** on the shell layers, so the launcher frosts the wallpaper rather than the
  terminal behind it.
- **`dim_modal`** exists and defaults **on** — a live behaviour not currently declared.
- **`noscreenshare`** layer rule exists and is not in use.
- **`misc:vrr = 2`** (fullscreen only) is the correct setting for a laptop + external; the FAQ
  warns that always-on VRR causes brightness swings on some panels.

Cost model, derived from the shaders rather than folklore: blur is **dual-Kawase** with fixed 5-tap
and 8-tap kernels, so `size` is essentially free and `passes` only adds ~12 % of blur work going
1→3. **The real cost is `damage.expand(size × 2^passes)`** — `size 3, passes 1` expands damage by
6 px; `size 8, passes 3` by 64 px; `size 16, passes 4` by 256 px. Raise `size` before `passes`.
Treat 40 as the real `size` ceiling despite the config allowing 100.

**`borderangle … loop` is banned outside a showcase profile.** Upstream's own wiki: it *"requires
Hyprland to constantly render new frames at a frequency equal to your screen's refresh rate … This
will apply even if animations are disabled or the affected decorations are not visible."* On this
machine that is 165 fps + 75 fps forever, on battery, defeating `misc:vfr` entirely.

**No plugins.** On **2026-05-12** `hyprwm/hyprland-plugins` PR #663 dropped every unmaintained
plugin; the repo now contains exactly four (borders-plus-plus, csgo-vulkan-fix, hyprbars,
hyprfocus). **hyprexpo, hyprtrails and hyprwinwrap are gone** — they survive in nixpkgs 25.11 at
`version = "0.52.0"` and are absent from unstable. The plugin repo's commit log is dominated by
`chase hyprland` roughly every two weeks. If a plugin is ever adopted it must come from
`pkgs.hyprlandPlugins.*` (built against the exact Hyprland in the closure, so a mismatch is a
**build failure**, not a runtime surprise) and **never** from `hyprpm`, which compiles at runtime
against system headers.

Native motion blur exists in **0.56** (`decoration:motion_blur:{enabled,samples}`); `decoration:glow:*`
and shadow gradients also land in 0.56; `blur:variant` and `decoration:wobble` are documented on
the git wiki but are **absent from 0.56.2's `ConfigValues.cpp`** — they are 0.57 material. Do not
plan around them.

#### Ownership impact

Unchanged.

#### Risks

All of the above is hyprlang and is subject to ADR-009's migration. The `decoration`/`animations`
*values* port cleanly; only the syntax changes.

#### Rollback

Per-setting; each is one line.

---

### ADR-011 — Event-drive the bar instead of polling it

**Status:** accepted
**Date:** 2026-09-17

#### Context

`waybar.service` has consumed 1053 s of CPU in 4 h 15 m (≈6.9 % of one core). Waybar itself
accounts for ~108 s; **~944 s (90 %) is forked `custom/*` scripts.**

#### Decision

Drive `custom/kblayout` from Hyprland's `activelayout` socket2 event rather than a 1-second poll,
and reduce `custom/gpu`'s cadence. Both currently lack a `signal`, so they cannot be event-driven
as written.

#### Why

`custom/kblayout` spawns `hyprctl -j devices` plus up to three `jq` invocations **once per second**
— roughly 15,400 process spawns per session — for data Hyprland already emits as an event, on the
very socket `hypr-dock-handler` is already connected to.

#### Ownership impact

`hypr-dock-handler` (or a sibling listener) gains responsibility for pushing layout changes to the
bar via `pkill -RTMIN+N waybar`, matching the existing signal convention (8 dnd, 9 efootball,
10 conservation, 11 mouseless).

#### Risks

The signal-number pairing is hand-maintained across two `let` blocks in one file. Keep the comment.

#### Rollback

Restore `interval = 1`.

---

### ADR-012 — Keep Alacritty; keep grim/slurp/Satty

**Status:** accepted
**Date:** 2026-09-17

#### Decision

**Terminal:** stay on Alacritty. **Screenshots:** keep the primitives, improve the workflow.

#### Why

**Ghostty** buys nothing here. Its `background-blur` is KDE-only on Linux — blur is compositor-side
and already configured. The scratchpad system does not use `--class`, so there is neither breakage
to fear nor capability to gain. Against it: on **2026-09-14** Ghostty merged PR #14052, replacing
`GtkGLArea` with a DMABUF-fed render surface; **the NVIDIA proprietary driver has no EGL DMABUF
export extension**, so NVIDIA falls back to a CPU memory copy, and reviewers on a GTX 1060 and an
RTX 3080 reported input lag — one at roughly a second. It was merged anyway, targeted at 1.4.0.
Adopting Ghostty now volunteers this RTX 3070 as the test bed. Revisit after 1.4.0 has sat in
unstable for a month.

The two real gains — ligatures and the Kitty graphics protocol for Yazi image previews — are
partly obtainable without switching: `pkgs.alacritty.override { withGraphics = true; }`, and yazi
from the existing unstable input (25.11 freezes yazi at 25.5.31).

**Screenshots:** the gap is workflow, not tooling. Add freeze (`hyprpicker -r -z`), window and
output subjects, and fix `GSK_RENDERER=ngl` → `gl`. For the outstanding instant-replay wishlist
item, `gpu-screen-recorder` is the only candidate that does NVENC without VAAPI, avoids the
Hyprland portal path, and has shadowplay-style replay as a first-class mode — with the caveat that
it is a one-developer project and 25.11 ships 5.9.0 against upstream 6.1.2.

#### Rollback

Per-item.

---

### ADR-013 — hypr* ecosystem: fix what is broken, adopt nothing new yet

**Status:** accepted
**Date:** 2026-09-17

#### Decision

- **Fix now:** `home/dani/wm/hyprlock.nix` sets `general.grace = 2` and
  `general.disable_loading_bar = true`. Neither key is registered in hyprlock **0.9.2 — the binary
  actually running**. Verified against `ConfigManager.cpp` at tag v0.9.2: `general` registers only
  `text_trim, hide_cursor, ignore_empty_input, immediate_render, fractional_scaling,
  screencopy_mode, fail_timeout`. hyprlock logs "Proceeding ignoring faulty entries" and carries
  on, so both have been silently no-ops. `grace` became a **CLI flag** in v0.9.0.
- **Checked, no action:** hyprsunset 0.3.3 (what 25.11 ships) predates the fix for a **100 % CPU
  busy-loop** in its Wayland event loop (PR #91, merged 2026-06-30, released in 0.4.0). Measured on
  this machine 2026-09-17: `CPUUsageNSec = 203,607,000` over 4 h 36 m — **0.001 % of a core.** The
  busy-loop does not reproduce here; no reason to pull hyprsunset from unstable.
- **Skip hyprcursor.** At scale 1.0 on 1440p its entire value proposition — crisp fractional
  scaling — is inert. nixpkgs' `bibata-cursors` builds `-p x11` only, so
  `home.pointerCursor.hyprcursor.enable` would export two env vars resolving to nothing and
  silently fall back to the XCursor already in use. GTK falls back regardless. Upstream's last
  release was **2025-07-31**.
- **Skip hyprpolkitagent for now.** nixpkgs is pinned at the Qt/QML **0.1.3** while upstream shipped
  a hyprtoolkit rewrite (**0.2.0**, 2026-09-09) — adopting now means theming Qt/Kirigami by hand
  and re-theming later. Revisit when `pkgs.hyprpolkitagent ≥ 0.2.0`.
- **Defer hyprshutdown.** It is the right answer to the problem solved by hand in commit `2f56460`.
  Not in 25.11. Note the correction: issue #17 ("Hangs on Logout with SDDM + NVIDIA") is still
  open, but **v0.1.1 ships merged PR #16, "Fix NVIDIA+SDDM logout hang with VT switch"**. The real
  risk for this machine is different and was nearly missed: v0.1.1 also ships PR #24, which
  migrated its exit dispatchers to **Hyprland 0.55+ Lua**. On 0.52.2 that is the failure mode that
  would actually bite.
- **Adopt staged hypridle listeners** — config-only, reversible, no new packages. Note
  `condition_cmd`/`condition_retry` do not exist in the 0.1.7 that 25.11 ships.

#### Also recorded

- **`hyprpwcenter` exists** (hyprwm, 150★, `pkgs.hyprpwcenter` 0.1.1 in 25.11). No HM module. It
  would replace pavucontrol, not anything currently in the repo.
- **hyprpanel was archived 2026-04-27**; the unstable attribute now *throws*. Its successor is
  `wayle` (`services.wayle` exists in HM 25.11; `pkgs.wayle` is **0.3.0 in the 25.11 channel** but
  absent from this repo's frozen pin — a channel bump, not a new input).
- **`hyprland-ctm-control-v1` is single-client.** Do not run a shell night-light module alongside
  hyprsunset; the loser is silently ignored.
- **`render:ctm_animation` defaults to "auto" = off on NVIDIA**, which is why hyprsunset
  transitions snap rather than fade here.

#### Rollback

Per-item.
