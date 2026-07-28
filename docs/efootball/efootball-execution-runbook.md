# eFootball performance changes — execution runbook

Four independent changes. Each has its own verification, so they can share one rebuild, but they
are committed separately so you can revert any one of them without losing the others.

| Task | What | Where it lives | Reboot? | Time |
|---|---|---|---|---|
| 1 | Refresh rate 60 → 75 / 165 | Hyprland (home-manager) | no | 15 min |
| 2 | Make GameMode actually engage | NixOS (`programs.steam`) | no | 15 min |
| 3 | Stop the 9 MB Wine trace | Steam UI only | no | 5 min |
| 4 | Platform profile → performance | NixOS + sysfs | maybe | 20 min |

Everything below is fish-safe. Where a command must run under bash it says so.

---

# Phase 0 — Before you touch anything

### 0.1 Preconditions

```fish
# laptop on AC power - task 4 behaves differently on battery
cat /sys/class/power_supply/AC*/online          # want: 1

# nothing else heavy running
pgrep -a steam
```

### 0.2 Record your rollback point

```fish
ls -1t /nix/var/nix/profiles/ | head -3
```

Yours currently reads `system-151-link`, so you are on **generation 151**. Write that number
down. After the rebuild you will be on 152, and `sudo nixos-rebuild switch --rollback` returns you
to 151. The boot menu also lists it if the machine won't come up.

### 0.3 Clean git state

```fish
cd ~/nixos-config
git status --short          # want: empty
git switch -c perf/efootball
```

If `git status` isn't empty, commit or stash first. You want every change below attributable to a
single commit.

### 0.4 Work out how home-manager is wired

This decides which command applies task 1.

```fish
rg -n 'homeConfigurations|home-manager.nixosModules|home-manager.users' ~/nixos-config/flake.nix ~/nixos-config/hosts/ 2>/dev/null
```

- Match on **`home-manager.users`** or **`home-manager.nixosModules`** → HM is a NixOS module.
  `nixos-rebuild switch` applies both system and home. **Call this integrated.**
- Match on **`homeConfigurations`** → HM is standalone. System and home need separate commands.
  **Call this standalone.**

Note which one you have; steps below refer back to it.

---

# Task 1 — Refresh rate

Your panels: `HDMI-A-1` (MSI MP273QP) is running 59.951 Hz and supports 75.00. `eDP-1` (internal)
is running 60.000 and supports 165.00. Both are being driven by whatever mode your config
requests, which is almost certainly `preferred` — and the EDID preferred mode on both is 60.

### 1.1 Test live, before editing anything

Nothing here persists. A reboot undoes it all.

```fish
hyprctl keyword monitor "HDMI-A-1,2560x1440@75,0x0,1"
```

Expected: the external screen blanks for roughly a second and returns.

```fish
hyprctl keyword monitor "eDP-1,2560x1440@165,2560x0,1"
```

Expected: same on the laptop panel.

### 1.2 Confirm the modes took

```fish
hyprctl monitors | grep -E '^Monitor|2560x1440@'
```

Expected output:

```
Monitor HDMI-A-1 (ID 0):
	2560x1440@75.00000 at 0x0
Monitor eDP-1 (ID 1):
	2560x1440@165.00000 at 2560x0
```

**If it still says 59.951 or 60.000**, the mode was rejected. Check the exact string Hyprland
accepts — it must be one of the strings from `availableModes`:

```fish
hyprctl monitors | rg -o 'availableModes.*' | tr ' ' '\n' | rg '2560x1440'
```

### 1.3 If a screen goes black

Type this blind (the shell still has focus even if you can't see it):

```fish
hyprctl keyword monitor "HDMI-A-1,preferred,0x0,1"
```

If that fails, unplug and replug HDMI. If everything is dark, `Ctrl+Alt+F2` gets you a TTY, log in,
and:

```fish
env HYPRLAND_INSTANCE_SIGNATURE=(ls -t /run/user/1000/hypr | head -1) hyprctl keyword monitor "HDMI-A-1,preferred,0x0,1"
```

Worst case: reboot. Nothing has been written to disk yet.

### 1.4 Live-test the games at the new rate

Before persisting, confirm the monitor genuinely runs 75 Hz without frame-skipping. Open
<https://www.testufo.com> in Firefox on the MSI. It should report ~75 fps and the frame-skipping
test should show no dropped frames. Some panels advertise 75 over HDMI and then skip.

### 1.5 Find the existing monitor config

```fish
rg -n --glob '!*.lock' 'monitor' ~/nixos-config/home/
```

You are looking for either:

```nix
# form A - settings list
wayland.windowManager.hyprland.settings.monitor = [
  "HDMI-A-1, preferred, 0x0, 1"
  "eDP-1, preferred, 2560x0, 1"
];
```

or

```nix
# form B - inside extraConfig
extraConfig = ''
  monitor = HDMI-A-1, preferred, 0x0, 1
'';
```

### 1.6 Edit

Replace the mode field only. Keep position and scale exactly as they are — changing them moves
your workspaces around.

Form A:

```nix
wayland.windowManager.hyprland.settings.monitor = [
  "HDMI-A-1, 2560x1440@75, 0x0, 1"
  "eDP-1, 2560x1440@165, 2560x0, 1"
];
```

Form B:

```nix
monitor = HDMI-A-1, 2560x1440@75, 0x0, 1
monitor = eDP-1, 2560x1440@165, 2560x0, 1
```

### 1.7 Commit

```fish
git add -A
git commit -m "feat(hyprland): drive both displays at their native refresh rates

HDMI-A-1 (MSI MP273QP) supports 75Hz and eDP-1 supports 165Hz, but both
were running at 60 because 'preferred' takes the EDID preferred mode.
Explicit modes remove a 16.7ms frame cadence that the hardware never
required."
```

### 1.8 Apply — wait for Task 2 and 4 first

Do not rebuild yet. Steps 2 and 4 add to the same rebuild.

### 1.9 Post-rebuild verification (come back to this)

```fish
hyprctl monitors | grep -E '^Monitor|2560x1440@'
```

Same expected output as 1.2. If the live test worked but the persisted config didn't, Hyprland
didn't reload — `hyprctl reload`, and if that doesn't do it, log out and back in.

### 1.10 In-game settings

1. Launch eFootball
2. Settings → Graphics (or Display) → Resolution: **2560x1440**
3. Display mode: **Fullscreen**, not Borderless / Windowed Fullscreen
4. Frame rate: **Unlimited** — the `DXVK_FRAME_RATE` in task 3's launch options bounds it
5. V-Sync: **Off**

Step 3 matters more than it looks. Borderless is what produces
`solitaryBlockedBy: windowed mode` in `hyprctl monitors`, which keeps Hyprland from handing the
game the display directly.

### 1.11 The mixed-refresh A/B (optional, later)

Two outputs at different refresh rates can upset XWayland frame pacing. Once you have baseline
frametime numbers, play one session with the unused panel off:

```fish
hyprctl keyword monitor "eDP-1,disable"
# restore afterwards
hyprctl keyword monitor "eDP-1,2560x1440@165,2560x0,1"
```

Compare frametime stdev between the two runs. Don't do this on the same night as the other
changes — one variable at a time.

---

# Task 2 — Make GameMode actually engage

Evidence this is broken, from your Proton log:

```
gamemodeauto: dlopen failed - libgamemode.so: cannot open shared object file
```

`gamemoderun` sets `LD_PRELOAD=libgamemodeauto.so`, that library loads, and then its `dlopen` of
`libgamemode.so` fails because the library isn't inside Steam's FHS sandbox. The request never
reaches the daemon. That is why your governor is still `powersave`.

### 2.1 Find the Steam config

```fish
rg -n 'programs.steam' ~/nixos-config/
```

Note the file path it prints. If nothing matches, Steam is enabled somewhere unusual — search
wider with `rg -n 'steam' ~/nixos-config/ | rg -v 'steamapps'`.

### 2.2 Check what's already set

```fish
rg -n -A8 'programs.steam' (rg -l 'programs.steam' ~/nixos-config/ | head -1)
rg -n -A5 'programs.gamemode' ~/nixos-config/
```

`gamemoderun` exists at `/run/current-system/sw/bin/gamemoderun`, so `programs.gamemode.enable` is
already true somewhere. You're adding to it, not creating it.

### 2.3 Edit the Steam block

```nix
programs.steam = {
  enable = true;
  extraPackages = with pkgs; [
    gamemode      # provides libgamemode.so inside the FHS - this is the fix
    mangohud
  ];
};
```

If `programs.steam` already has other attributes, leave them; only add `extraPackages`. If
`extraPackages` already exists, append to the list.

### 2.4 Edit the GameMode block

```nix
programs.gamemode = {
  enable = true;
  settings = {
    general = {
      renice = 10;
      inhibit_screensaver = 1;
    };
    custom = {
      start = "${pkgs.writeShellScript "gamemode-start" ''
        ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance
        ${pkgs.libnotify}/bin/notify-send -u low "GameMode" "on — profile: performance"
      ''}";
      end = "${pkgs.writeShellScript "gamemode-end" ''
        ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set balanced
        ${pkgs.libnotify}/bin/notify-send -u low "GameMode" "off — profile: balanced"
      ''}";
    };
  };
};
```

Three things to know about this block:

- `custom.start` takes **one** command, which is why the profile switch and the notification are
  bundled into a single generated script rather than being two separate settings.
- This is also Task 4's persistence mechanism. It depends on `services.power-profiles-daemon`
  being enabled — see 4.4.
- The notification is deliberate. It is the fastest possible signal that the fix worked: no toast
  when the game starts means GameMode still isn't engaging.

If the file doesn't already have `pkgs` in scope, its header needs to read
`{ config, lib, pkgs, ... }:`.

### 2.5 Commit

```fish
git add -A
git commit -m "fix(steam): expose libgamemode.so inside the Steam FHS environment

gamemoderun was preloading libgamemodeauto.so successfully, but its
dlopen of libgamemode.so failed inside the sandbox, so GameMode never
activated and the CPU stayed on the powersave governor during matches.
Adds a notify hook so activation is visible."
```

### 2.6 Now rebuild (tasks 1, 2 and 4 together)

Add task 4's one-liner (step 4.4) before running this.

```fish
cd ~/nixos-config
sudo nixos-rebuild switch --flake .#legionix
```

or your usual `nh os switch .`. If HM is **standalone** (from 0.4), also run
`nh home switch .` or `home-manager switch --flake .#dani@legionix`.

Expected tail: `activating the configuration...` with no red text. On success:

```fish
ls -1t /nix/var/nix/profiles/ | head -3     # should now show system-152-link
```

**If the rebuild fails**, read the first error, not the last. The two likely ones here are
`error: undefined variable 'pkgs'` (fix the module header, 2.4) and
`error: The option 'programs.steam.extraPackages' does not exist` (you edited a home-manager file
by mistake — `programs.steam` is a NixOS option).

### 2.7 Fully exit Steam

Steam builds its FHS environment once, at launch. A running client will not see the new packages.

```fish
# Steam menu → Exit, then confirm:
pgrep -a steam                # expect: no output
pkill -f steamwebhelper       # only if the above printed something
```

Relaunch Steam.

### 2.8 Verify

Start a match — a Trial Match vs COM is fine, this doesn't need to be online.

Immediately:

```fish
gamemoded -s
```

Expected: `gamemode is active`. Previously: `gamemode is inactive`.

```fish
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
```

Expected: `performance`. Previously: `powersave`.

You should also have seen the desktop notification at launch.

**If `gamemoded -s` still says inactive:**

1. Confirm the library is now inside the sandbox:
   ```fish
   steam-run bash -c 'ls -la /usr/lib/libgamemode*'
   ```
   (If `steam-run` isn't installed: `nix shell nixpkgs#steam-run`.) You want
   `libgamemode.so.0` to exist. If it doesn't, `extraPackages` didn't land — re-check 2.3 and that
   you restarted Steam.
2. Confirm `gamemoderun` is still in the launch options (task 3's string keeps it).
3. Re-run with logging on for one session and grep:
   ```fish
   rg 'gamemodeauto' ~/steam-1665460.log
   ```
   No matches at all = the fix worked. Still `dlopen failed` = it didn't.

---

# Task 3 — Stop the Wine trace

Your saved launch options start with `PROTON_LOG=1`, and the resulting log is 9.2 MB of
`trace:seh:` and `trace:mscoree:`. eFootball throws a large number of SEH exceptions and every one
is being unwound and written to disk mid-match.

### 3.1 Create the log directory first

```fish
mkdir -p ~/mangologs
```

MangoHud will not create it and silently writes nothing if it's missing.

### 3.2 Replace the launch options

Steam → Library → right-click **eFootball™** → Properties → General → Launch Options. Select the
whole existing string and replace it with:

```
SDL_VIDEODRIVER=x11 __GL_MaxFramesAllowed=1 __GL_SHADER_DISK_CACHE_SIZE=12000000000 __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1 DXVK_FRAME_RATE=75 MANGOHUD_CONFIG=fps,frame_timing=1,gpu_name,gpu_stats,gpu_temp,cpu_stats,cpu_temp,vram,ram,output_folder=/home/dani/mangologs,log_duration=180,toggle_logging=F2 gamemoderun mangohud %command%
```

Field by field:

| Fragment | Why |
|---|---|
| `SDL_VIDEODRIVER=x11` | yours, kept — affects SDL input handling |
| `__GL_MaxFramesAllowed=1` | shrinks the NVIDIA queued-frame buffer, direct latency win |
| `__GL_SHADER_DISK_CACHE_SIZE=...` | your cache is only 25 MB, so it keeps evicting and recompiling |
| `DXVK_FRAME_RATE=75` | matches the MSI at its new rate. Use `162` if you play on the laptop panel |
| `output_folder=...` | where the frametime CSV lands |
| `log_duration=180` | logging stops itself after 3 minutes |
| `toggle_logging=F2` | starts logging on demand |
| `gamemoderun mangohud` | wrapper order matters: gamemode outermost |

`PROTON_LOG=1` is deliberately absent.

### 3.3 Delete the old log

```fish
ls -la ~/steam-1665460.log      # 9.2M
rm -f ~/steam-1665460.log
```

### 3.4 Verify the launch options actually saved

Steam only writes `localconfig.vdf` when it exits, so this check needs Steam closed:

```fish
rg -o '"LaunchOptions".*' ~/.local/share/Steam/userdata/*/config/localconfig.vdf
```

Expected: your new string, with no `PROTON_LOG=1`.

### 3.5 Verify no log is being written

Play two minutes, then:

```fish
ls -la ~/steam-1665460.log
```

Expected: `No such file or directory`.

### 3.6 Verify MangoHud logging works

Press **F2** at kickoff. Play three minutes.

```fish
ls -la ~/mangologs/
python3 frametime-report.py ~/mangologs/*.csv
```

Expected: at least one CSV, and a report with a median frametime near 13.3 ms if you're at 75 Hz.

**If no CSV appears**, the game is swallowing F2. Two fallbacks — edit the launch options and
replace `toggle_logging=F2` with either `toggle_logging=Shift_L+F2` or `autostart_log=10`, which
starts logging ten seconds after launch with no keypress at all.

### 3.7 Keep the crash-hunting variant

Save this somewhere retrievable — a comment in your Nix config, or a fish abbreviation. You will
want it again if crashes survive:

```
PROTON_LOG=1 <the entire string from 3.2>
```

---

# Task 4 — Platform profile

An i7-12700H with a 3070 Laptop is mostly governed by firmware policy. If the profile is
`balanced` or `low-power`, you are capping both CPU boost and GPU TGP before any of the above
matters.

### 4.1 Does the interface exist?

```fish
cat /sys/firmware/acpi/platform_profile_choices
cat /sys/firmware/acpi/platform_profile
```

Expected on a working Legion: something like `low-power balanced performance` and then one of
those. **If you get "No such file or directory", go to 4.2. Otherwise skip to 4.3.**

### 4.2 If the interface is missing

```fish
lsmod | rg -i 'legion|ideapad|thinkpad_acpi'
nix search nixpkgs lenovo-legion
```

The out-of-tree module:

```nix
boot.extraModulePackages = [ config.boot.kernelPackages.lenovo-legion-module ];
```

This one **does** need a reboot, and it is out-of-tree, which means a future kernel bump can fail
to build it. If a rebuild breaks months from now with an error mentioning `legion`, this line is
why. If you'd rather not carry that, skip task 4 entirely — the other three still stand on their
own — or set the power mode in BIOS instead (Legion: `Fn+Q` cycles it at runtime on many models).

### 4.3 Test by hand

```fish
echo performance | sudo tee /sys/firmware/acpi/platform_profile
cat /sys/firmware/acpi/platform_profile
```

Expected: `performance` echoed back.

Now start a match and, in a second terminal, watch what the GPU is permitted to do:

```fish
nvidia-smi --query-gpu=pstate,clocks.sm,power.draw,temperature.gpu,utilization.gpu --format=csv -l 2
```

Expected under load: `P0`, SM clocks roughly 1200–1700 MHz, temperature climbing to 70–80 °C.

Your triage snapshot showed `P8 / 210 MHz / 51 °C` because nothing was running — that's idle, not
a problem.

**If pstate stays P8 or P5 while the game is clearly running**, the GPU isn't being asked to do
much (eFootball at 1440p may genuinely not tax a 3070) — check `utilization.gpu`. Low utilisation
with high fps is fine and means nothing is wrong.

### 4.4 Persist it

The GameMode hook in 2.4 already calls `powerprofilesctl`. It needs the daemon:

```nix
services.power-profiles-daemon.enable = true;
```

First check you aren't running TLP — the two conflict and the rebuild will error if both are on:

```fish
rg -n 'tlp' ~/nixos-config/
```

If you do use TLP, drop `services.power-profiles-daemon` and instead make the sysfs node writable
by your group with a udev rule, then have the GameMode hook write to it directly:

```nix
services.udev.extraRules = ''
  ACTION=="add", SUBSYSTEM=="platform", KERNEL=="acpi-*", RUN+="${pkgs.coreutils}/bin/chgrp wheel /sys/firmware/acpi/platform_profile", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/firmware/acpi/platform_profile"
'';
```

### 4.5 Commit

```fish
git add -A
git commit -m "feat(gamemode): switch platform profile to performance during play

Hooks powerprofilesctl into gamemode start/end so the Legion firmware
profile follows the game session instead of being set by hand, and
returns to balanced afterwards."
```

### 4.6 Verify the hook, not just the profile

During a live match:

```fish
powerprofilesctl get
```

Expected: `performance`. Quit the game, wait five seconds, run it again — expected `balanced`.

**If it stays balanced during the match**, the hook didn't fire. Distinguish the two causes:

- `gamemoded -s` says inactive → task 2 didn't work, fix that first; the hook can't fire.
- `gamemoded -s` says active but the profile didn't change → the polkit action is refusing. Test
  by hand: `powerprofilesctl set performance` in a terminal. If that also fails, the daemon isn't
  running: `systemctl status power-profiles-daemon`.

### 4.7 Note on AC and noise

Performance mode generally only unlocks fully on AC, and the fans get loud. That is the deal with
a 3070 Laptop that's allowed its full TGP. If the noise is unacceptable, `balanced` with the other
three changes still leaves you far ahead of where you started.

---

# Phase 5 — Verification pass

Start a match, and in a second terminal:

```fish
bash efootball-verify.sh
```

Every line should be green. The mapping when one isn't:

| Failed check | Go to |
|---|---|
| governor ≠ performance | 2.8 |
| gamemode inactive | 2.8 |
| dlopen failed still in proton log | 2.3, then 2.7 |
| proton log exists | 3.2, 3.4 |
| platform_profile ≠ performance | 4.6 |
| refresh rate still 60 | 1.9 |
| `solitaryBlockedBy: windowed mode` | 1.10 step 3 |

---

# Phase 6 — First measured session

Only now is a measurement meaningful.

1. Trial Match vs COM. Press F2 at kickoff. Play 3 minutes.
2. One online match. Press F2 at kickoff.
3. ```fish
   python3 frametime-report.py ~/mangologs/*.csv
   ```
4. Record, for each: median frametime, 1% low, stdev, and your own 1–5 responsiveness score.

At 75 Hz the median frametime should be near 13.3 ms; at 165 Hz near 6.1 ms. If the median is
still near 16.7 ms, the game is capped at 60 somewhere — check the in-game frame rate setting
(1.10 step 4) and `DXVK_FRAME_RATE`.

---

# Phase 7 — Rollback

**One task at a time** (preferred):

```fish
cd ~/nixos-config
git log --oneline -4          # find the commit
git revert <sha>
sudo nixos-rebuild switch --flake .#legionix
```

**Everything at once:**

```fish
sudo nixos-rebuild switch --rollback     # back to generation 151
```

**Task 3 only** (no Nix involved): put the old launch options string back in the Steam dialog.

**Task 4 only, temporarily:**

```fish
echo balanced | sudo tee /sys/firmware/acpi/platform_profile
```

**If the machine won't boot**: pick generation 151 from the systemd-boot menu at startup. Nothing
in this runbook touches the bootloader, kernel or filesystem, so a non-booting system is very
unlikely.

---

# Acceptance checklist

- [ ] `hyprctl monitors` shows `2560x1440@75.00000` and `2560x1440@165.00000`
- [ ] testufo reports ~75 fps with no skipped frames on the MSI
- [ ] eFootball is in exclusive fullscreen at 2560x1440, in-game cap off, v-sync off
- [ ] `gamemoded -s` says active during a match
- [ ] Desktop notification appears when a match starts
- [ ] `cat .../scaling_governor` says `performance` during a match
- [ ] `rg 'gamemodeauto' ~/steam-1665460.log` returns nothing (run once with logging on to confirm)
- [ ] `~/steam-1665460.log` does not exist after a normal session
- [ ] A CSV lands in `~/mangologs` after pressing F2
- [ ] `powerprofilesctl get` says performance during, balanced after
- [ ] `efootball-verify.sh` is all green
- [ ] Frametime median near 13.3 ms (75 Hz) or 6.1 ms (165 Hz)
- [ ] Branch merged: `git switch master; git merge perf/efootball`

---

# Deliberately not in this runbook

Tearing, `direct_scanout`, `noblur`/`noanim` window rules, gamescope, Proton version bisecting and
the network work. All are still on the table — but they are the next round. Adding them here would
mean eleven simultaneous changes and no way to attribute the result to any of them.
