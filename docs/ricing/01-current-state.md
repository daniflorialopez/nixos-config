# Current-State Inventory

> Compiled 2026-09-17 from the repository at `55365b3` and from the live `legionix`
> session (generation 207, booted 12:52). Where the repo and the running system
> disagree, both are recorded.
>
> **This is a description, not a plan.** Judgements about what to change live in
> `06-decisions.md`; open work lives in `08-implementation-tracker.md`.

## Executive summary

This is **not a greenfield rice**. It is a mature, heavily-commented Hyprland desktop
with an existing design system (`docs/design-system.md`), a calibrated palette, a
custom launcher stack carrying two local upstream patches, and a documented recovery
runbook. Most of what a ricing project would normally *build* already exists here in
some form. The work is therefore consolidation and elevation, not construction.

Three facts dominate every decision that follows:

1. **There is no usable text console on legionix.** `Ctrl+Alt+F<n>` yields a blank
   VT. Recovery is exactly two paths: the systemd-boot generation menu, or SSH over
   Tailscale. Anything that breaks both is unrecoverable without a live USB.
2. **The greeter rides on `services.xserver.enable`,** which is commented as a
   Cinnamon dependency. Removing Cinnamon naively removes the only graphical login.
3. **The palette has ~200 hardcoded literals across ~15 files with no shared source.**
   Any runtime theme engine must first be given an abstraction that does not yet exist.

---

## Repository

| | |
|---|---|
| flake root | `/home/dani/nixos-config` |
| hosts | `legionix` (this machine), `danix-hp`, `danixos-vm` |
| nixpkgs | `github:NixOS/nixpkgs/nixos-25.11`, locked `b6018f8` @ 2026-06-30 |
| nixpkgs-unstable | `github:NixOS/nixpkgs/nixos-unstable`, locked `1559d3d` @ 2026-07-30 |
| Home Manager | `release-25.11`, locked `3ee51fb` @ **2026-05-23** — ~5 weeks *older* than the nixpkgs it follows |
| HM integration | NixOS module (`home-manager.nixosModules.home-manager`), `useGlobalPkgs`, `useUserPackages`, `backupFileExtension = "hm-backup"` |
| user module root | `home/dani/` → `shell/`, `programs/` (unconditional) + `wm/` (gated) |
| overlays | **none**; customisation is per-call-site `.override` / `.overrideAttrs` |
| `nixpkgs.config` | only `allowUnfree = true` (`modules/nixos/base.nix:95`) |
| flake outputs | `nixosConfigurations` only — no `checks`, `packages`, `devShells`, `formatter` |

### Pinning strategy

**Nothing is tag-pinned.** Every input tracks a moving branch; `flake.lock` is the
only pin. Five of ten inputs follow the root nixpkgs; `nixos-hardware`, `elephant`
and `walker` each drag in a private nixpkgs, so a `legionix` switch evaluates
**four** nixpkgs trees. What actually builds walker is `nixpkgs_4` (2026-04-09), a
tree this repo never inspects.

Desktop-critical provenance:

| Package | Source | Live version | unstable has |
|---|---|---|---|
| hyprland | nixpkgs 25.11 | **0.52.2** | 0.56.1 |
| hyprpaper | **nixpkgs-unstable** | 0.8.4 | 0.8.4 |
| hyprlock / hypridle / hyprsunset / hyprpicker | nixpkgs 25.11 | 0.9.2 / 0.1.7 / 0.3.3 / 0.4.5 | newer |
| waybar | nixpkgs 25.11 | 0.14.0 | 0.15.0 |
| walker | **flake input, locally patched ×2** | 2.16.2 | — |
| elephant | **flake input** (via walker's `follows`) | 2.21.0 | not in 25.11 at all |
| mako / swayosd / satty / grim / slurp | nixpkgs 25.11 | 1.10.0 / 0.2.1 / 0.20.0 / 1.5.0 / 1.5.0 | newer |
| sddm + sddm-astronaut | nixpkgs 25.11 | `kdePackages.sddm`; theme is a `-unstable-2025-01-05` snapshot | |
| quickshell | **not installed** | — | present in 25.11 |

`hyprpaper` is the only desktop package taken from unstable. The compositor is four
minor releases behind unstable.

`elephant` as a root input is **load-bearing but invisible**: it is never referenced
as `inputs.elephant`; its only job is to be walker's `follows` target. Deleting it as
"unused" would un-pin elephant, not remove it.

---

## Hosts

| | legionix | danix-hp | danixos-vm |
|---|---|---|---|
| Hyprland | yes | **yes** | no (import commented out) |
| X server / SDDM | yes | yes | no |
| Cinnamon | yes | yes | yes (inert — no X server) |
| Default session | `hyprland-uwsm` (`mkForce`) | `hyprland-uwsm` (`mkForce`) | none; TTY login |
| GPU | NVIDIA proprietary 580.142, `open = false` | `modesetting` | `modesetting` |
| Disk | plain `disko.nix` | plain `disko.nix` | **`disko-luks.nix`** |
| HM `wm/` tree | yes | **yes** | no |

`hosts/legionix/desktop.nix` and `hosts/danix-hp/desktop.nix` are **byte-identical**.
Every desktop change lands on danix-hp unchanged; only the GPU driver differs.

The VM's sole protection is `hyprEnabled` at `home/dani/default.nix:10`. `home/dani/shell/`
and `home/dani/programs/` are imported unconditionally on all three hosts — a desktop
dependency leaking into either directory is the realistic way to break the VM build.

The mechanical guard is **`check-all`** (`modules/nixos/rebuild-ergonomics.nix:8-21`):
`nix flake check` plus a toplevel build of all three hosts. Its host list is hardcoded.

---

## Desktop ownership map

One row per responsibility, as it actually is today.

| Responsibility | Owner | Module | Notes |
|---|---|---|---|
| compositor | Hyprland 0.52.2 | `modules/nixos/desktop/hyprland.nix`, `home/dani/wm/hyprland.nix` | UWSM-managed session; `systemd.enable = false` on the HM side |
| session manager | UWSM 0.24.3 | `programs.hyprland.withUWSM = true` | session id `hyprland-uwsm` |
| bar | waybar 0.14.0 | `home/dani/wm/waybar.nix` | three floating glass islands, 14 modules, 10 custom scripts |
| launcher / command plane | **walker + elephant** | `home/dani/wm/walker.nix` | 4 hand-written GTK4 themes, 2 local patches |
| menus / pickers | elephant providers | `walker.nix`, `wallpaper.nix`, `hyprland.nix` | scratchpad board, logout confirm, wallpaper contact sheet |
| notifications | **mako** | `home/dani/wm/hyprland-services.nix:84` | `default-timeout = 0`; DND via `mako mode` |
| clipboard history | **elephant `clipboard` provider** | `home/dani/wm/clipboard.nix` | 12 h TTL, 100 items, plaintext `.gob` |
| wallpaper | **hyprpaper (unstable)** | `home/dani/wm/wallpaper.nix` | static; no transitions |
| wallpaper picker | walker `dani-wall` theme + elephant Lua menu | `wallpaper.nix`, `walker.nix` | replaced waytrogen on 2026-09-16 |
| OSD (volume/brightness) | swayosd | `home/dani/wm/swayosd.nix` | styled to match the bar |
| lock | hyprlock | `home/dani/wm/hyprlock.nix` | blurred screenshot; **no idle auto-lock by choice** |
| idle | hypridle | `home/dani/wm/hyprlock.nix:81` | lock-on-suspend + dpms-on-resume only |
| night temperature | hyprsunset | `hyprland-services.nix:147` | 3-step time profile |
| polkit agent | **polkit-gnome** | `hyprland-services.nix:168` | not hyprpolkitagent |
| GTK theme | HM `gtk.*` → `adw-gtk3-dark` + Papirus-Dark | `home/dani/wm/theme.nix` | **contested by dconf — see conflicts** |
| Qt theme | env only (`QT_QPA_PLATFORMTHEME=adwaita`, `QT_STYLE_OVERRIDE=adwaita-dark`) | `theme.nix:28-35` | no `qt5ct`/`qt6ct` dirs |
| cursor | Bibata-Modern-Ice 32 | `home/dani/wm/cursor.nix` | XCursor only; **no hyprcursor** |
| icons | Papirus-Dark | `theme.nix` | |
| fonts | **CaskaydiaMono Nerd Font only** | `modules/nixos/fonts.nix` | no UI sans-serif declared anywhere |
| terminal | Alacritty | `home/dani/shell/alacritty.nix` | opacity 0.96, 13 pt |
| shell | fish + starship | `shell/fish.nix`, `shell/starship.nix` | vi mode; no rebuild abbreviations |
| file manager | pcmanfm (GUI), yazi (TUI) | `programs/apps.nix`, `programs/yazi.nix` | |
| screenshots | grim + slurp + satty | `hyprland.nix:8` (`screenshot-satty`) | region-only; no window/output/freeze modes |
| recording | **nothing** | — | obs-studio installed, unconfigured |
| greeter | **SDDM (X11) + sddm-astronaut** | `modules/nixos/desktop/sddm.nix` | Wayland greeter deliberately disabled |
| boot splash | Plymouth `bgrt` | `modules/nixos/base.nix:44` | firmware logo + NixOS watermark |
| boot manager | systemd-boot | `base.nix:13` | `configurationLimit = 3`, timeout 2 s |
| theme engine | **none** | — | no Stylix, no Matugen; ~200 literals across 15 files |
| Hyprland plugins | **none loaded** | — | `hyprctl plugin list` → empty |

---

## Monitors

Declared (`home/dani/wm/hyprland.nix:314-317`) and live state agree exactly.

```text
connector:      HDMI-A-1                    eDP-1
description:    MSI MP273QP (27")           laptop panel
resolution:     2560x1440                   2560x1440
refresh:        74.999 Hz (panel max)       165.003 Hz (panel max)
scale:          1.0                         1.0
position:       0x0                          2560x0
VRR:            false (never configured)     false
reserved:       0 42 0 0 (waybar)           0 42 0 0
workspaces:     1, 4-10                     2, 3
```

`misc:vfr = 1`; `misc:vrr` is unset (default 0). `AQ_DRM_DEVICES=/dev/dri/card1` is
written unconditionally to `~/.config/uwsm/env-hyprland` — **hardcoded, and applied
on danix-hp too**.

Monitor connector names are hardcoded in **five** places: the monitor list, the
workspace rules, `wall-set`'s heredoc, hyprpaper's `ExecStartPre` heredoc, the dead
`wall-apply`, and the dock handler.

---

## Keybindings

84 live binds, **zero collisions** (verified against `hyprctl binds`). Everything is
`bindd` (bind + description) because the descriptions feed the `$mod+/` palette.
Full table is in the repo's own `docs/home.md`; the ricing-relevant subset:

| Chord | Action | Recovery-critical? |
|---|---|---|
| `$mod+Return` | Alacritty | **yes — the emergency terminal** |
| `$mod+Space` | walker launcher | |
| `$mod+S` | scratchpad board (12 tiles) | |
| `$mod+Tab` | window switcher (walker) | |
| `$mod+P` / `$mod SHIFT+P` | clipboard history / wipe | |
| `$mod CTRL+W` | wallpaper contact sheet | |
| `$mod+Escape` | hyprlock | |
| `$mod SHIFT+Escape` | logout confirm (walker) | **yes — and it routes through walker** |
| `$mod+/` (`code:61`) | keybinds palette | |
| `$mod+M` | Mouseless toggle | |
| `Print` | screenshot → satty | |

**keyd rewrites `$mod+C` → `Ctrl+Insert` and `$mod+V` → `Shift+Insert`** at the evdev
layer, before Hyprland sees them. Any bind on those two chords is dead code. This is
why clipboard history is on `P`.

---

## Services

Nine user units, all healthy, **zero failed**. All are `PartOf=graphical-session.target`
with no `BindsTo`, so each restarts independently without ending the session.

| Unit | Restart | X-Restart-Triggers | RSS |
|---|---|---|---|
| waybar | on-failure / 100 ms | **yes ×2** (config + style) | 59 MB |
| mako | on-failure / 100 ms | **no** | 10 MB |
| hyprpaper | always / 10 s | yes (outer conf only) | 123 MB |
| hypridle | always / 10 s | yes | 8 MB |
| hyprsunset | always / 10 s | yes | 7 MB |
| swayosd | always / 2 s | style path is inside `ExecStart` | 67 MB |
| walker | on-failure / 100 ms | yes (config + themes) | 66 MB |
| elephant | on-failure / 1 s | yes (menus.toml options) | **125 MB** |
| hypr-dock-handler | on-failure / 100 ms | no | 3 MB |
| polkit-gnome-agent | on-failure / 100 ms | no | 27 MB |

One failed **system** unit: `flatpak-remotes.service`, permanently, on every boot
(races DNS, soft-handles the failure, then still exits 1).

### Measured idle cost

```text
CPU idle          93.2 – 93.9 %
Memory            3.9 GiB used / 15.4 GiB
Swap              0 B used (zram, never touched in 4 h)
GPU               26 % utilisation, 837 MiB VRAM, 53 °C at desktop idle
Shell total       ~463 MB RSS / ~680 MB by cgroup
```

**The notable finding:** `waybar.service` has consumed 1053 s of CPU in 4 h 15 m
(≈6.9 % of one core). Waybar itself accounts for ~108 s of that; **~944 s (90 %) is
forked `custom/*` scripts.** `custom/kblayout` polls `hyprctl -j devices` through up
to three `jq` invocations **once per second** — ~15,400 process spawns per session —
and has no `signal`, so it cannot be event-driven as written. Hyprland emits
`activelayout` on socket2, which `hypr-dock-handler` is already connected to.

26 % GPU at idle is the compositor paying for blur + shadows on two 1440p outputs at
75/165 Hz, entirely on the dGPU (there is no iGPU on this machine).

---

## Theme ownership

The palette is Tokyo Night (moon family), documented with deliberate deviations in
`docs/design-system.md`:

- **Blue `#7aa2f7` is the accent; orange `#ff9e64` is the attention tier only.**
- Sunset gradient `#e0af68 → #ff9e64 → #f7768e` means *load/escalation*, not decoration.
- **No cyan** — Dani cannot reliably distinguish cyan from blue/white; its roles went
  to orange, and surviving "cyan" is rendered as teal `#4fd6be`.
- Contrast calibrated to **WCAG AAA (≥7:1 on `#1a1b26`)**; several values are
  lightened from canon. `#737aa2` is the floor for hint text.
- One font: CaskaydiaMono Nerd Font.

These are **design constraints, not defaults**. A generator that simply emits a
Material scheme regresses all four.

### Where colour actually lives

There is **no shared palette source**. `home/dani/wm/theme.nix:39-51` writes
`waybar/palette.css`, and its only consumer is the `@import` in `waybar.nix:552`.
Everything else re-types the literals.

| Surface | File | Literals | Syntax |
|---|---|---|---|
| waybar | `wm/theme.nix` + `wm/waybar.nix` | via `palette.css` | GTK `@define-color` |
| walker (4 themes) | `wm/walker.nix` | copied | GTK CSS |
| mako | `wm/hyprland-services.nix:90-104` | copied | `#rrggbbaa` |
| swayosd | `wm/swayosd.nix:17-47` | copied | GTK CSS |
| Hyprland borders/glass | `wm/hyprland.nix` | copied | `rgba()` |
| hyprlock | `wm/hyprlock.nix` | copied | `rgba()` |
| SDDM greeter | `modules/nixos/desktop/sddm.nix` | copied | `#rrggbb` strings |
| alacritty | `shell/alacritty.nix` | 22 | **`0xrrggbb`** |
| fish | `shell/fish.nix` | 36 | **bare `rrggbb`, no `#`, unquoted** |
| starship | `shell/starship.nix` | 7 | named-palette — cheapest to retarget |
| tmux | `shell/tmux.nix` | 17 | numbered slots, no semantics |
| zellij | `shell/zellij.nix` | **94** | `#rrggbb` |
| btop | `shell/btop.nix` | 42 | `#rrggbb`, 7 ordered gradients |
| yazi / zathura / imv / lazygit | `programs/*.nix` | ~50 | mixed |

Four incompatible syntaxes. **A regex on `#[0-9a-f]{6}` misses all 21 of fish's bare
hexes.** Two values are not colours at all and must survive untouched:
`btop.theme_background = false` and fish's `bg = -1` (both mean "inherit terminal
transparency"), as does `alacritty.window.opacity = 0.96`.

Note that Alacritty's 0.96 and Hyprland's 0.94/0.88 **multiply**: a focused terminal
renders at ~0.90, unfocused ~0.84. Two independent opacity knobs for one window.

---

## Recovery paths

This section is load-bearing. Verified live.

| Path | State |
|---|---|
| Emergency terminal | **`$mod+Return`.** Alacritty is installed at *system* level (`modules/nixos/desktop/hyprland.nix:27`), so it survives a failed HM activation. |
| TTY | **DOES NOT EXIST.** `/sys/class/vtconsole/` holds only `vtcon0` = "(S) dummy device". `Ctrl+Alt+F<n>` gives a blank screen. Documented at `docs/rescue-blackscreen.md:97-99`. |
| SSH | **Primary out-of-band rescue.** sshd + tailscaled both active, `legionix.tail4bc4b5.ts.net` / 100.104.81.99, pubkey-only. |
| Shell restart | `systemctl --user restart waybar` / `walker` / `mako` — each independent. |
| Exit Hyprland without the shell | `hyprctl dispatch exit` (hyprctl is on the system profile). The *bound* logout goes through walker+elephant. |
| Static fallback wallpaper | **WEAK.** `default.png` lives in the mutable `~/Pictures/Wallpapers`, not the store; nothing validates that the selected path still resolves. |
| Generation rollback | systemd-boot menu, **3 entries** (24 generations exist on disk). Tap `Space` after the Lenovo logo. |
| Safe-graphics fallback | **Deliberately absent.** Tried 2026-07-29 (`327fa80`), reverted hours later (`2f20532`) — nouveau-on-Ampere froze the panel every way it was tested. Do not re-propose. |
| On-box runbook | `rescue` on PATH, pages `docs/rescue-blackscreen.md` from the store. |

### Recovery gaps found

1. **No text console** (above) — every keyboard-only procedure that assumes one is fiction.
2. **Boot menu offers 3 generations; the runbook promises 10.** A regression noticed
   after three switches is already unrollable from the firmware menu.
3. **waybar renders on the *bottom* layer despite `layer = "top"`.** Verified:
   `hyprctl layers` puts waybar at level 1 with levels 2 and 3 empty. `$mod+F` is
   `fullscreen, 0`, which covers it — and the waybar button is the only
   mouse-reachable escape from a Mouseless keyboard grab.
4. **The only bound logout routes through walker, which `Requires=elephant.service`.**
   If elephant fails to start there is no keyboard-bound way to end the session. The
   working fallback (`systemctl start logout-to-greeter.service`, passwordless via the
   scoped polkit rule) is documented nowhere.
5. **No declarative password for dani; root is locked; `/etc` is outside restic.**
   After a reinstall or restore, nothing can authenticate. This is exactly the state
   the LUKS migration produces.

### Mouseless — the special hazard

Mouseless takes an exclusive `EVIOCGRAB` on every keyboard, which bypasses the
kernel's own `kbd` and `sysrq` handlers: **`Ctrl+Alt+F2` and Magic SysRq do not fire.**
The mouse is never grabbed. Escapes are (1) the waybar button, (2) `mouseless-panic`
over SSH, (3) the power button. `modules/nixos/keyd.nix:14`'s `-736e` vendor exclusion
prevents the keyd↔Mouseless feedback loop that wedged every keyboard on 2026-08-12 —
removing it re-arms that. Separately, `input` group membership lets any process
running as dani read every keystroke; the safer `mouseless-scoped.nix` exists and is
switched off.

---

## Custom scripts

35 derivations (31 `writeShellApplication`, 1 `writeShellScript`, 3 `writeText`).
Full table with runtimeInputs, state paths and invocation is reproduced in the
inventory appendix of this project; the fragility summary:

| Script | Issue |
|---|---|
| `hyprpaper-init-selected` | the only script with **no PATH wrapper** (`writeShellScript` takes no `runtimeInputs`) — `mkdir`/`cat`/`dirname` resolve from ambient PATH |
| `wall-apply` | **dead code**; a second, divergent wallpaper setter that does not persist |
| `wall-set` + `hyprpaper-init-selected` | two heredocs encoding the same file format, must stay byte-compatible |
| `hypr-dock-handler` | `sleep 1` races mode negotiation; `Restart=on-failure` means a clean `socat` exit leaves it dead and silent |
| `scratchpad` | 5 s poll then `exit 0` — a slow Chromium PWA leaves an unsized window with no message |
| `keybinds-menu` | dispatches on walker's dmenu **index** against a parallel temp file; an off-by-one would fire the wrong bind silently |
| `waybar-bt-toggle` | uses `grep` without declaring it in `runtimeInputs` |
| `waybar-kblayout` | 1 s poll, no signal — the dominant CPU cost on the machine |
| `pwcopy`, `clipboard-wipe` | rely on `elephant` from session PATH; outside the session the pause silently fails and the secret **does** enter history |

Five scripts deliberately rely on session PATH rather than `runtimeInputs`
(`elephant`, `walker`, `nvim`) because those come from flake inputs, not nixpkgs.
Each is a documented choice and each is a silent-failure path outside the session.

---

## `~/.config` ownership

Every HM symlink points into one store path. **Ownership is settled**: no `.hm-backup`
newer than 2026-05-21, and every desktop-critical tree (`hypr/`, `waybar/`, `walker/`,
`elephant/`, `mako/`, `gtk-3.0/`, `gtk-4.0/`, `alacritty/`, `fish/`, `zellij/`,
`tmux/`, `yazi/`, `zathura/`, `lazygit/`, `bat/`) is store-symlinked with no mutable
stragglers.

Legitimate mutable state:

```text
~/.local/state/hypr/hyprpaper-selected.conf   the wallpaper choice (sourced by HM's conf)
~/.local/state/wallpaper/current              the same, for scripts
~/.local/state/wallpaper/debug.log            84 KB, unrotated, grows forever
~/.cache/wallpaper-thumbs/                    20 files, md5-named
~/.cache/elephant/clipboard.gob               plaintext, mode 0600, 12 h TTL
~/Pictures/Wallpapers/                        activation-seeded, user-owned (20 images)
~/.config/fish/fish_variables                 fish universal variables
```

Unmanaged residue that is live and visible:

| Path | Note |
|---|---|
| `~/.config/dconf/` | **sets `font-name = 'Ubuntu 10'`** for every GTK app — see conflicts |
| `~/.config/waytrogen/` | 1.1 MB cache of a tool removed on 2026-09-16 |
| `~/.config/xdg-terminals.list`, `hyprland-xdg-terminals.list` | both name `org.gnome.Terminal.desktop`, present only because Cinnamon is installed |
| `~/.config/nvim/` | entirely outside HM — seeded once from `lazyvim-starter`, marker-guarded |
| `~/.config/git/ignore` | mutable while `git/config` is HM-owned |
| `~/.config/alacritty/alacritty.toml.4788adb6.bak` | stale, read-only, unread |

---

## Known conflicts and technical debt

58 findings were verified during the inventory. The ones that matter for ricing,
by severity.

### High

1. **GTK appearance is co-owned by HM `settings.ini` and mutable dconf, and dconf
   wins through the Settings portal.** `busctl` confirms the portal returns
   `font-name = "Ubuntu 10"` — a Cinnamon-era value no file in the repo sets. The two
   agree on theme/icons/cursor **by coincidence only**; changing `gtk.theme` in HM
   leaves the stale dconf value in place for anything reading via the portal, so a
   retheme will half-apply.
2. **`xdg.portal` has three writers, and the Home Manager set silently shadows the
   system set.** `NIX_XDG_DESKTOP_PORTAL_DIR` points at the per-user profile, which
   contains only `gtk.portal` and `hyprland.portal`. The seven-entry system
   `extraPortals` list is mostly dead weight, and the Secret portal that Cinnamon pays
   for never loads. Any future portal backend added system-side will appear to do
   nothing.
3. ~~`mako.service` has no `X-Restart-Triggers`, so settings edits never reach the
   daemon.~~ **Checked and withdrawn, 2026-09-17.** The HM mako module sets
   `onChange = "${cfg.package}/bin/makoctl reload || true"` on `mako/config`, and it is
   present in the live activation script. Config edits *do* apply. Adding a restart
   trigger would in fact be worse than the status quo — a restart drops queued
   notifications, which `default-timeout = 0` makes meaningful, whereas `reload`
   preserves them. The only real defect here is that the hand-written unit hardcodes
   `${pkgs.mako}` instead of `config.services.mako.package`; both resolve to the same
   store path today, so it is latent rather than live.
4. **mako has two start paths.** The hand-written unit coexists with the HM module's
   D-Bus activation file (`org.freedesktop.Notifications`, via `dbus.packages`).
   Stopping `mako.service` does not disable mako — the next notification activates a
   second, untracked instance outside the cgroup with no restart policy. Edge case
   (it only bites when deliberately stopping mako), but worth knowing.
5. **Two Firefox builds; the system default browser is the policy-free one.**
   `mimeapps.nix:58` uses `${pkgs.firefox}` (unwrapped, `policies.json = {}`) while
   PATH has the wrapped build with the three force-installed extensions. Every link
   opened from another app gets the one without uBlock Origin.
6. **waybar draws on the bottom layer** (recovery gap #3 above).
7. **No text console** (recovery gap #1 above).
8. **`services.xserver.enable = true` is commented as a Cinnamon dependency but is
   what the only login path rides on.** Removing Cinnamon — an obvious cleanup, since
   it drags in ~20 services, Touchégg, 16 dead autostart units and two portal
   backends — takes the X server away from a greeter that is deliberately not Wayland.
   Combined with the missing TTY, that is a one-line change that removes the machine's
   only interactive entry point.
9. **walker is built from an unpinned moving branch with two local patches against its
   internals.** `nix flake update` can move it arbitrarily far; the
   `walker-window-per-theme` patch's first hunk is a `use` list that rustfmt will
   reorder the moment upstream touches it. Mitigating: patch failure aborts the build
   loudly rather than regressing at runtime.
10. **`AQ_DRM_DEVICES=/dev/dri/card1` is hardcoded and written on danix-hp too.**
    Even on legionix the index is enumeration luck — there is no `card0`.
11. **`flatpak-remotes.service` is permanently failed by design flaw**, so
    `systemctl --failed` is never empty and a genuinely new failure has no signal to
    stand out against.
12. **`disko.nix` declares a 2-partition 100 % layout for a disk that holds a 349 GB
    Windows install**, with nothing in-tree saying it is used only to generate
    `fileSystems`. Running disko's destructive path would wipe Windows.

### Medium

13. **The Tokyo Night palette has four independent owners** (`palette.css`, swayosd,
    mako, walker) and `palette.css` is namespaced under `waybar/` so the others cannot
    import it as written.
14. **The wallpaper has two owners that agree only by coincidence.** SDDM pins
    `wallhaven-jevzkp.jpg` at build time; the desktop reads mutable runtime state.
    Picking any other wallpaper desynchronises the greeter permanently, with no error.
    (hyprlock uses `path = screenshot`, so lock follows the desktop.)
15. **Workspace→monitor mapping is duplicated** between the Hyprland rules and a shell
    `case` glob in `hypr-dock-handler`, with no mechanical link.
16. **`scratchpads.toml` and `logout.toml` still carry the elephant rescan race** that
    `wallpapers.lua` was fixed for. They get away with it only because they rarely change.
17. **`elephant/clipboard.toml` is a raw `xdg.configFile` with no `onChange`**, so the
    clipboard TTL — the stated bound on plaintext exposure — goes stale mid-session
    exactly when tightened.
18. **`~/.config/mimeapps.list` and `btop.conf` are read-only store symlinks that the
    applications try to write.** "Set as default" and every in-TUI btop change are
    silently discarded.
19. **Two Neovim builds**; yazi and every file manager launch the unwrapped one,
    without LazyVim's tool dependencies on PATH.
20. **`waybar-kblayout` polls once a second** (perf, above).
21. **HM's pin is 5 weeks older than the nixpkgs it follows**, and three inputs do not
    follow nixpkgs at all.
22. **Firefox extensions install from unpinned AMO `latest.xpi` URLs** — not
    reproducible; Vimium intercepts keystrokes.
23. **SDDM's background resolves a path inside the `.gitignore`d wallpaper directory**,
    alive only because those 16 files predate the ignore rule. `git rm --cached` breaks
    the greeter at build time.
24. **No store-backed fallback wallpaper** (recovery, above).
25. **`hypr-dock-handler` `Restart=on-failure`** on a watcher loop (should be `always`).

### Obsolete

- `wall-apply` — dead code, never even built.
- `unstablePkgs` binding in `hyprland-services.nix:3` — unused, and it is what
  `docs/architecture.md:160` cites as evidence that file pulls from unstable.
- `lazyvim-starter` — inert; the seed marker means bumping the input changes nothing.
- `keyd-vibranium-practice.nix` — dormant module, import commented out.
- `mouseless-scoped.nix` — the strictly safer variant, switched off.
- Touchégg — runs in every session, declared nowhere, a transitive Cinnamon dependency.

---

## Things that are already good — do not disturb

These are load-bearing and the reasoning is not re-derivable from the code.

1. **`hyprpaper.conf` as a 4-line `source =` indirection into mutable state.** The
   cleanest HM→runtime escape hatch in the repo: HM keeps the file, runtime keeps the
   choice, no rebuild to change wallpaper.
2. **`home.activation.wallpaperLibrary` ordered `entryAfter [ "linkGeneration" ]`**
   (not `writeBoundary`) — as a sibling it could have run first and left
   `linkGeneration` trying to `rm` a symlink it no longer recognised.
3. **Declaring walker themes and elephant menus through module options rather than raw
   `xdg.configFile`**, so they land in `X-Restart-Triggers`. Plus the `onChange`
   `try-restart` on `wallpapers.lua`, which is the only construct that guarantees the
   file exists before the daemon rereads it.
4. **waybar's two `X-Restart-Triggers`** on the rendered config and style.
5. **Splitting the two walker fixes into independent patch files**, so either can be
   dropped alone, with build-time failure as the intended mode.
6. **The environment split:** `hyprland.conf` contains zero `env =` lines; session
   environment lives in `uwsm/env-hyprland` and `environment.d/`.
7. **The `hyprEnabled` gate** — the single conditional keeping the whole `wm/` tree off
   the VM.
8. **Self-hiding waybar leaves** (`command -v nvidia-smi`, `systemctl cat …`,
   `[ -e $node ]`) — host-awareness pushed into the leaf scripts, which is what lets
   one waybar config serve both real hosts.
9. **`check-all`** — the only mechanical guard against breaking danix-hp or the VM.
10. **keyd's `-736e` exclusion** — removing it re-arms the 2026-08-12 keyboard wedge.
11. **`security.pam.services.hyprlock`** living next to `programs.hyprland` — without
    it, and with no text console, a locked session is a permanent lockout.
12. **Alacritty installed at system level**, so `$mod+Return` still yields a terminal
    after a failed HM activation.
13. **`logout-to-greeter.service` + its narrow polkit rule** — the documented
    workaround for Hyprland core-dumping on NVIDIA teardown.
14. **`efootball-block` and `mouseless-scoped` deliberately not `wantedBy` anything** —
    a reboot clears a stateful toggle, which is the correct default.
15. **`programs.bat` using `theme = "ansi"`** — the one place the terminal palette is
    the single source of truth, and the pattern a generator would want everywhere.
16. **The design system itself** (`docs/design-system.md`) and the accessibility
    deviations it encodes.

---

## Documentation state

`docs/` is unusually complete and mostly accurate. Known-stale claims:

- waytrogen is still described as the live wallpaper picker in `docs/operations.md:146`,
  `docs/home.md:287,289`, `docs/architecture.md:42,159`.
- `docs/architecture.md:127` lists 7 `wm/` imports; there are 9.
- `docs/home.md:345` says walker has three themes; there are four.
- `docs/modules.md:21` says Plymouth uses Breeze; it uses `bgrt`.
- `docs/rescue-blackscreen.md:26` promises 10 boot entries; there are 3.
- `docs/operations.md:20` says a 1 s boot menu; it is 2 s.
- `docs/home.md:236` says `$mod+M` is the file manager; it is Mouseless.
- `home/dani/wm/mouseless.nix` and `modules/nixos/flatpak.nix` are undocumented —
  the former is the most safety-critical undocumented file in the repo.
- `CLAUDE.md` still frames the eFootball work as four pending tasks; three are done.
- `CLAUDE.md` and `AGENTS.md` are two agent guides with no cross-reference.

## Git state

Branch `ricing`, **identical to `master`** — zero commits, no upstream tracking. The
ricing docs are untracked. 257 commits total, single author. Commit discipline is
genuinely followed: of the last 50 commits, 33 touch 1–2 files; median 2 files, ~30
lines. Recent commit *bodies* are the primary design documentation — they quote
journal lines with timestamps and measured values, and record load-bearing invariants
that appear nowhere in the `.nix` files.

### Tried and reverted — landmines for a future agent

- **safe-graphics specialisation** (added and reverted within hours, 2026-07-29).
- **Global glow** on walker/window borders (added 2026-03-17, removed 2026-03-22).
- **Ghostty as the terminal** (2026-01-20, config deleted 2026-02-11).
- **Wallpaper fit modes** — removed as never having worked; only `cover` is valid.
- **A wallpaper preview pane** — walker fills Preview only on selection *change*, so it
  opens empty, and an empty Preview box is transparent: a 400 px hole in the card.
- **Routing logout through UWSM** — SDDM reads the non-zero exit as a crash and never
  restarts the greeter (24 s of dead console, 2026-09-08 22:57:48).
- **Hyprland-managed services via `exec-once`** — replaced by systemd user units
  (2026-02-28). Do not move them back.
- **Maximize-style fullscreen** — replaced by true `fullscreen, 0`.
- **CapsLock remapping** — removed as conflicting.
