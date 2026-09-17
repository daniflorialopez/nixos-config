# Channel bump: nixos-25.11 → nixos-26.05

> Scoped 2026-09-17. Every version below was evaluated against both channels; every
> source claim was checked against the file at the exact branch. Empirically verified
> items say so. Items I could not confirm are marked **UNVERIFIED** and are carried as
> risks rather than hidden.
>
> **Read `docs/rescue-blackscreen.md` before starting.** On legionix there is no usable
> text console. If the display does not come back, your only paths are the systemd-boot
> generation menu and SSH over Tailscale.

## Why this is riskier here than a normal channel bump

One switch changes three things at once:

| | 25.11 | 26.05 |
|---|---|---|
| Kernel (default `linuxPackages`) | **6.12.93** (LTS) | **6.18.52** — six minor series |
| NVIDIA (`nvidiaPackages.stable`) | **580.142** | **595.71.05** — a driver generation |
| initrd implementation | scripted | **systemd stage 1** — the default flips silently |

The third is the dangerous one, because it is the only change that can fail *before* a
graphical modeset. `boot.initrd.systemd.enable` goes from `mkEnableOption` (false) in
25.11 to `default = true` in 26.05, and this repo never sets it.

**Mitigation: pin it false in the same commit.** Adopt systemd stage 1 afterwards as its
own revertable commit. That costs one extra reboot and removes one variable from the
step that can strand you. (It is deprecated with removal scheduled for 26.11, so this is
a deferral of months, not a permanent opt-out.)

## What is *not* a risk — checked, so nobody re-litigates it

- **Ampere is supported at 595.71.05.** NVIDIA's own `supportedchips.html` for that exact
  version lists `NVIDIA GeForce RTX 3070 Laptop GPU`, device ID `24DD` — this machine's
  GPU (`lspci`: `10de:24dd`). `kernel_open.html` confirms the proprietary flavour still
  supports Turing/Ampere/Ada/Hopper; only Blackwell+ is open-modules-only.
- **`NVreg_EnableGpuFirmware=0` is still a registered module parameter** at 595.71.05
  (`kernel-open/nvidia/nv-reg.h`: `__NV_ENABLE_GPU_FIRMWARE`, `NV_DEFINE_REG_ENTRY`,
  `NV_DEFINE_PARAMS_TABLE_ENTRY`). `nv-firmware-registry.h` is byte-identical between
  580.173.02 and 595.71.05. So the "modprobe rejects an unknown option and the module
  never loads" catastrophe does **not** apply.
- **`docker_29` still exists** on 26.05 (29.7.2, a real attribute, no alias warning).
  `modules/nixos/virtualisation.nix` pins it by name and would have failed eval for all
  three hosts at once. `docker_28` now *throws*; the repo does not use it.
- **`sddm-astronaut` still accepts `embeddedTheme` and `themeConfig`** — the greeter
  builds. Its upstream commit is ~16 months newer, so unknown theme keys would land in
  the generated INI and be ignored: the failure mode is *wrong colours*, not *no greeter*.
- **`plymouth.nix` is byte-identical** between the branches. `theme = "bgrt"` is fine.
- **systemd-boot module**: three hunks, none semantic. `configurationLimit`, `editor`,
  `consoleMode` untouched.
- **`fileSystems.*.fsType` is now mandatory** — disko sets it explicitly, so this is a
  non-issue here.
- **hyprlang is not removed.** Hyprland 0.55.4 picks its parser by file extension; `.conf`
  still goes to the legacy parser. This is *not* a rewrite-into-Lua project.

## Step 0 — make the rollback real, BEFORE anything else

`configurationLimit = 10` is committed (`cbf5d79`) but **the ESP still holds three
entries**. The limit only takes effect when the bootloader is next installed.

```
sudo nixos-rebuild boot --flake .#legionix
reboot
```

Then, at the Lenovo logo, tap `Space` and **count the entries**. Do not proceed until you
have seen roughly ten. This menu is what every boot-time risk below falls back to.

Also, before you need them:

```
nixos-rebuild list-generations        # write down the current good generation number
ssh dani@legionix                     # from your phone, over Tailscale — prove it works now
```

Do not let `programs.nh.clean` run between the bump and your confirmation.

## Step 1 — the bump commit

This has to be **one commit**, which is unusual for this repo and is forced by the
change: the new Hyprland rule grammar is invalid on 0.52.2, and `configType` /
`sideloadInitLua` do not exist in HM 25.11. There is no ordering that leaves an
intermediate commit working. You revert "the bump", not its pieces.

### 1a. `flake.nix`

```
nixpkgs.url      = "github:NixOS/nixpkgs/nixos-26.05";
home-manager.url = "github:nix-community/home-manager/release-26.05";
```

Then a **scoped** lock update — not a bare `nix flake update`:

```
nix flake update nixpkgs home-manager
```

`disko`, `agenix` and `nix-index-database` follow `nixpkgs` and move with it. `walker`
and `elephant` are on unpinned default branches — **do not** include them; bumping the
launcher at the same time as the kernel and the GPU driver is how you lose the ability to
tell which one broke.

### 1b. Pin the initrd (see above)

```nix
# modules/nixos/base.nix
boot.initrd.systemd.enable = false;
```

### 1c. Home Manager: one real breakage, six warnings

**The breakage — silent, and it eats your editor.** On 26.05 `programs.neovim` writes
`~/.config/nvim/init.lua` whenever its auto-populated `initLua` is non-empty, and it is
always non-empty now (provider lines). This repo owns `~/.config/nvim` imperatively via
the LazyVim seed, and `init.lua` is a real file containing `require("config.lazy")`. With
`backupFileExtension = "hm-backup"`, the first switch renames it and symlinks HM's
four-line stub. **LazyVim never bootstraps. No error, no assertion.**

```nix
programs.neovim.sideloadInitLua = true;   # verified by eval: init.lua.enable becomes false
```

The six stateVersion-gated defaults all take the legacy branch (`home.stateVersion =
"25.05"` < `"26.05"`), so behaviour is preserved — but each emits a warning on every
rebuild until pinned explicitly:

```nix
wayland.windowManager.hyprland.configType = "hyprlang";
programs.firefox.configPath = ".mozilla/firefox";
gtk.gtk4.theme = config.gtk.theme;
programs.yazi.shellWrapperName = "yy";
programs.neovim.withPython3 = true;   # or false to adopt the new default
programs.neovim.withRuby = true;      # or false
```

Two of these are landmines if `home.stateVersion` is ever bumped to 26.05:
`configType` silently becomes `lua` (the entire `settings` block would be re-rendered as
`hl.*()` calls), and `firefox.configPath` relocates all three profiles so Firefox starts
from scratch. Pinning them now makes that a deliberate future choice.

### 1d. Hyprland 0.52.2 → 0.55.4: every rule line is a hard parse error

Verified by running `Hyprland --verify-config` from the real 0.55.4 build against the
config home-manager generates: 20 errors. Everything else — `monitor`, `bindd`, `bindm`,
`input`, `general`, `decoration`, `blur`, `shadow`, `animations`, `workspace` — parses
clean.

These are *per-line* errors, not fatal. Hyprland starts, drops the bad rules, and shows a
red overlay. So the failure mode is a visibly broken desktop, not a brick — but
`check-all` now catches it at build time (`7009f98`).

**`misc.vfr`** — delete the line. `misc:vfr` does not exist in 0.55.4 (it moved to
`debug:vfr`, which already defaults true). Do not substitute `debug.vfr = true`; that is
a no-op that only adds noise.

**`windowrulev2` → `windowrule`**, and the grammar changed shape: every effect needs an
explicit value, and matchers need a literal `match:` prefix.

| current | replacement |
|---|---|
| `"float, class:^(xdg-desktop-portal-gtk)$"` | `"float true, match:class ^(xdg-desktop-portal-gtk)$"` |
| `"center, class:^(xdg-desktop-portal-gtk)$"` | `"center true, match:class ^(xdg-desktop-portal-gtk)$"` |
| `"size 50% 65%, class:^(xdg-desktop-portal-gtk)$"` | `"size 50% 65%, match:class ^(xdg-desktop-portal-gtk)$"` |
| `"float, class:^(firefox)$, title:^(Save As\|Guardar como).*$"` | `"float true, match:class ^(firefox)$, match:title ^(Save As\|Guardar como).*$"` |
| `"size 70% 75%, class:…, title:…"` | `"size 70% 75%, match:class …, match:title …"` |
| `"center 1, class:…, title:…"` | `"center true, match:class …, match:title …"` |
| `"bordersize 0, fullscreenstate:1 *"` | `"border_size 0, match:fullscreen_state_internal 1"` |
| `"rounding 0, fullscreenstate:1 *"` | `"rounding 0, match:fullscreen_state_internal 1"` |
| `"opacity 1.0 override 1.0 override, class:^(mpv\|imv\|…)$"` | `"opacity 1.0 override 1.0 override, match:class ^(mpv\|imv\|…)$"` |
| `"opacity 1.0 override 1.0 override, title:^(Picture-in-Picture)$"` | `"opacity 1.0 override 1.0 override, match:title ^(Picture-in-Picture)$"` |

Notes: effect names are snake_case now (`bordersize` → `border_size`). `fullscreenstate`
split into two int props, and `*` is no longer a wildcard — express "any" by omitting the
prop. Regex matching is unchanged, so patterns port as-is (keep the Nix `\\.` escaping).

**`layerrule`** — `ignorezero` is gone entirely. Its exact equivalent is `ignore_alpha 0`
(the shader discards on `alpha <= 0`, which is what `ignorezero` meant).

| current | replacement |
|---|---|
| `"blur, waybar"` | `"blur true, match:namespace waybar"` |
| `"ignorezero, waybar"` | `"ignore_alpha 0, match:namespace waybar"` |
| `"blur, walker"` | `"blur true, match:namespace walker"` |
| `"ignorealpha 0.4, walker"` | `"ignore_alpha 0.4, match:namespace walker"` |
| `"blur, notifications"` | `"blur true, match:namespace notifications"` |
| `"ignorezero, notifications"` | `"ignore_alpha 0, match:namespace notifications"` |
| `"blur, swayosd"` | `"blur true, match:namespace swayosd"` |
| `"ignorezero, swayosd"` | `"ignore_alpha 0, match:namespace swayosd"` |
| `"noanim, mouseless-overlay"` | `"no_anim true, match:namespace mouseless-overlay"` |

**One behaviour change to accept consciously:** `center 1` on the Firefox *Save As*
dialog currently centres on the full monitor, ignoring waybar's reserved strip. In 0.55.4
`center` always centres in the work area and the ignore-reserved variant was removed. The
dialog will sit slightly lower. There is no replacement rule; an explicit `move` rule is
the fix if it matters.

**`hyprctl keyword` still works**, but is now hyprlang-only — `dispatchKeyword` returns
`"keyword can't work with non-legacy parsers. Use eval."` under the Lua parser. A future
effect-profile system built on `hyprctl keyword` is therefore explicitly coupled to
*not* migrating to Lua. One asymmetry to design around: dynamic `windowrule` registers
with the live engine immediately, but `layerrule` does **not** — layer changes need a
reload.

## Step 2 — verify before installing

```
check-all
```

This now does `nix flake check`, builds all three hosts, **and** runs
`Hyprland --verify-config` per host against the generated config. Expect a long run: the
closed NVIDIA module is unfree, so Hydra does not publish it and
`nvidia-kernel-modules-595.71.05-6.18.52` compiles locally.

```
nvd diff /run/current-system <the legionix toplevel>
```

## Step 3 — install

```
sudo nixos-rebuild boot --flake .#legionix
```

**`boot`, never `switch`.** The running generation stays untouched and the current
default stays default until you reboot. 26.05 will refuse `switch` anyway: the dbus
implementation default flips to `dbus-broker` and 26.05 registers a switch inhibitor for
it. That refusal is a guardrail — do not defeat it with `NIXOS_NO_CHECK=1`.

Reboot, and **pick the new generation explicitly from the menu** rather than letting it
boot as default. Then a black screen is cured by a power-cycle back into the old default,
instead of a menu pick made under stress.

## If the display does not come back

SSH in and run these in order. The two that discriminate fastest are marked.

```
uname -r                                          # did we actually boot 6.18.52?
cat /proc/driver/nvidia/version                   # is the 595 module loaded at all?
lsmod | grep -E '^nvidia'
cat /sys/module/nvidia_drm/parameters/modeset      # <-- must be Y
ls /dev/dri/                                       # <-- card1 absent = module never bound
dmesg | grep -iE 'nvrm|nvidia|gsp|firmware'
cat /sys/module/nvidia/parameters/NVreg_EnableGpuFirmware
systemctl --failed
systemctl status display-manager.service
journalctl -b --user -u 'wayland-wm@*' -e
hyprctl monitors
```

`modeset = N` means the modprobe.d migration is the culprit, not the driver (26.05 moves
the nvidia modeset params off the kernel cmdline into `/etc/modprobe.d/nixos.conf`).
`card1` absent means the kernel module never bound — initrd or driver, not the compositor.

### Repair

```
sudo nixos-rebuild boot --rollback
reboot
```

If the driver is the culprit but everything else is fine, the cheapest forward fix is one
line — it decouples "move to 26.05" from "move to the 595 driver":

```nix
hardware.nvidia.branch = "legacy_580";   # 580.173.02, LTSB supported to Aug 2028
```

## Open risks to test deliberately after a successful boot

| Risk | How it presents | Test |
|---|---|---|
| **Suspend/resume on the legacy path.** `open = false` keeps this host on `NVreg_PreserveVideoMemoryAllocations`; 595's successor (`NVreg_UseKernelSuspendNotifiers`) is gated on the open modules and nixpkgs asserts it. There is a reported 595.71.05 suspend regression. | suspend aborts, or resume returns black | close the lid deliberately, before you rely on it |
| **Pageflip timeout under Wayland at 595.71.05** — reported total freeze, power-cycle only, no upstream fix. Reported on kwin, not Hyprland. | random hard freeze minutes-to-hours in; `"Pageflip timed out!"` in the journal | use it for a day before trusting it |
| **GA104 non-GSP init path at 595.** The param is accepted (verified); whether the path still works on Ampere in the 595 closed RM is **UNVERIFIED**. | `/dev/nvidia*` absent, RM init failure in dmesg | if hit: delete the `boot.extraModprobeConfig` line — one line, independently revertable. Do **not** also set `gsp.enable = false`; the firmware needs to stay in the store for the fallback |
| **Mixed 75 Hz + 165 Hz on 595.** Weak evidence only (a 2024 report on drivers 551–565, GPU unstated). | one head dark after modeset | if hit, try 165 → 120 temporarily |
| **SDDM PAM stacks were rewritten** into structured rules with `useDefaultRules = false`. Not build-detectable. | greeter renders, correct password rejected | fix over SSH or roll back |
| **`sddm-astronaut` theme keys** may have drifted over ~16 months upstream. | wrong colours at the greeter | cosmetic; fix at leisure |

## Deliberately *not* in this commit

- The NVIDIA branch pin (`legacy_580`) — that is the repair, not the plan.
- Any GSP cleanup.
- `walker` / `elephant` bumps.
- Adopting systemd stage 1 (do it after, separately).
- Anything from `docs/ricing/08-implementation-tracker.md`.

The value of this repo's one-change-per-commit rule is that each of those stays
independently revertable. A channel bump is already the largest single change the repo
takes; do not make it larger.
