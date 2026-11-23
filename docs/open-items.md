# Open items — everything deliberately left out or unfinished

The one place that lists what is **not** done: paused work, parked branches,
known gaps, and the investigation notes needed to pick each one up again.
Last updated 2026-11-17. If you finish something here, delete it here in the
same commit.

Context: on 2026-10-22 a gap study listed 17 things this machine lacked as a
personal OS (status table at the bottom). Work since then has been one feature
per branch, merged into master only after a real test.

---

## 1. Disk encryption (LUKS) — paused until back home

**Done and merged:** 1a systemd stage 1 on legionix; 1b remote unlock ported
to systemd stage 1 (drills 1 + 2 re-passed on the VM, two bugs fixed); 1c disko
can no longer wipe Windows (`destroy = false`, pinned GUIDs; Drill 4 passed
with an identical before/after fingerprint). Runbook: [luks-runbook.md](luks-runbook.md).

**Why it is paused:** migration day needs to be at home: physical access, the
installer USB, a network cable for the remote-unlock test, fast internet
(legionix's system is 37 GiB; the VM's 30 GB install took over an hour on
travel Wi-Fi), and room for the Steam library.

**Still to do before migration day:**

- **1d — declarative password.** legionix sets no password option, so the
  reinstalled `dani` gets a locked `!` (nixpkgs `update-users-groups.pl`).
  `passwd` then asks for a current password that does not exist and `sudo`
  needs one: a lockout. The drills only passed because the VM has
  `initialPassword = "changeme"`. Plan: an agenix secret + 
  `users.users.dani.hashedPasswordFile` (agenix already decrypts before users
  are created: `users.deps = [ "agenixInstall" ]`). Prerequisite for
  impermanence too.
- **1e — keep the host identity.** `/etc` is not in restic, and
  `/etc/ssh/ssh_host_ed25519_key` is what decrypts every agenix secret (restic
  password and env, and 1d's password). Copy it, plus `/var/lib/tailscale`
  (keeps the tailnet node and its IP 100.104.81.99), into the `--extra-files`
  tree before wiping.
- **Check legionix for a stale LUKS header.** Drill 4 found that `mkfs.btrfs`
  leaves the first 64 KiB alone, so an old LUKS header can survive under a
  btrfs and make disko skip `luksFormat`. legionix ran Omarchy before, which
  encrypts by default. Read-only check: `sudo wipefs /dev/nvme0n1p2` (only
  `btrfs` = clean). The migration-day sequence already wipes p2's signatures,
  so this is about knowing, not fixing.
- **VM rehearsal assets are stale.** Drill 4 created a new LUKS container, so
  the Bitwarden item `danixos-vm LUKS recovery` and
  `~/.local/share/danixos-vm-rehearsal/luks-header.img` belong to the old one.
  Redo Drill 1 setup and Drill 2 step 1 before the next rehearsal.
- **Drill 3 has not been re-run** under systemd stage 1 (Drill 4 exercised the
  same reinstall path, but not the "nothing left" story).
- **Steam (319 GB) is excluded from restic.** Park it on an external disk or
  plan the re-download.
- **Decide on impermanence** before migration day, and add a `/home` subvolume
  (plus one for Steam) in the same reinstall — needed by gap item 3.
- **Windows is not encrypted.** Its partition is plain NTFS, not BitLocker, so
  after LUKS a thief can still read Windows files. Separate decision; note
  BitLocker can ask for its recovery key after bootloader updates when Windows
  is chainloaded from systemd-boot.

## 2. Parked branch `feat/resolved-dns` (gap item 2) — until back home

Not switched; Dani chose to wait while travelling. The branch makes DNS go
through systemd-resolved so it no longer depends on tailscaled (boot-time
failures, the 2026-10-21 backup error). Test plan: switch, then
`sudo systemctl stop tailscaled; resolvectl query example.com` must still answer.

- **Keep Tailscale's "Override local DNS" ON while travelling.** It routes all
  lookups through tailscaled to Google over DNS-over-HTTPS (verified: an
  established connection to `[2001:4860:4860::8888]:443`), so travel Wi-Fi can
  neither read nor spoof them. Turning it off would trade that for captive-portal
  convenience. Captive portals meanwhile: `tailscale down`, log in,
  `tailscale up`.

## 3. PipeWire real-time scheduling (follow-up from gap item 8) — wait for 26.11

**Decided 2026-11-17: wait for the 26.11 bump, then re-check.** No audible
problem (no crackles); this is about fragility, not sound.

What the 2026-11-17 read-only check found (supersedes the "never RT" below):

- `pipewire` and `wireplumber` **do** get RT: their `data-loop.0` is
  `SCHED_RR` priority 20, granted by rtkit directly (rtkit journal:
  "Successfully made thread … RT at priority 20").
- `pipewire-pulse` does **not**: its `data-loop.0` stays `SCHED_OTHER`. It asks
  through xdg-desktop-portal 1.20.4, which still fails with
  `Realtime error: Could not get pidns for pid …: Could not fstatat ns/pid: Not a directory`.
- Which route a process takes depends on start order at login: module-rt
  uses the portal only if it is already on the bus, otherwise asks rtkit.
  This boot: pipewire + wireplumber 23.15 s, portal 23.22 s, pipewire-pulse
  23.30 s - a ~70 ms race. The 2026-10-25 failure was pipewire restarted by
  hand while the portal was up, i.e. the same race lost.
- Effect: apps speaking PulseAudio (Firefox, Steam, Proton games) pass
  through one non-RT hop; the final mix is RT. Inaudible on a 14-core CPU
  unless it is saturated.

**On 26.11 (from 2026-12-20):** re-run the check -
`ps -L -o tid,cls,rtprio,ni,comm -p (pgrep -x pipewire-pulse)` (fish) and
`journalctl --user -b -u xdg-desktop-portal | grep -i realtime`. If the portal
error is gone and all three `data-loop.0` threads show `RR`, close this item.
If not, the fixes considered were: (1) RLIMIT_RTPRIO for the user session so
module-rt sets RT itself, bypassing rtkit and the portal - first verify the
limit reaches user@.service; (2) order pipewire-pulse before the portal -
cheap but keeps the dependency on start order.

What was established (2026-10-25):

- rtkit works: a direct `MakeThreadRealtimeWithPID` call got "Successfully made
  thread … RT at priority 10" in its journal.
- PipeWire's `module-rt` asks through xdg-desktop-portal's Realtime interface
  first. That fails on every call, in the portal's journal:
  `Realtime error: Could not get pidns for pid …: Could not fstatat ns/pid: Not a directory`
  — while PipeWire logs "acquired realtime priority 20 … using RTKit". Likely
  an upstream portal bug (pidfd handed where a /proc dirfd is expected).
- The portal also caches rtkit's limits at its own startup: right after the
  switch it reported MaxRealtimePriority 0 until `systemctl --user restart
  xdg-desktop-portal`. A fresh login does the same.
- `context.properties = { module.rt.args = { rtportal.enabled = false … } }` in
  a drop-in is loaded but does not change module-rt's behaviour.
- `module.rt = false` plus an own `libpipewire-module-rt` entry with
  `rtportal.enabled = false` does bypass the portal ("Portal Realtime
  disabled") and rtkit then grants **nice -11** — but the data loop never gets
  RT, presumably because a drop-in's module loads after the data loop exists
  (the default entry is first in `context.modules` for that reason).
- Debugging recipe: `systemctl --user set-environment PIPEWIRE_DEBUG='mod.rt:5'`,
  restart pipewire, read `journalctl --user -u pipewire`, then
  `unset-environment`. Thread policy: `chrt -p <tid>` per
  `/proc/<pid>/task/*`.

Next ideas: check the xdg-desktop-portal version against upstream issues;
replace `context.modules` wholesale so the portal-free module-rt is first;
or set `RLIMIT_RTPRIO` for the user session so module-rt needs neither.

## 3b. Power menu leftovers (gap item 9)

- **No Suspend card - declined 2026-11-17.** Suspend itself works (lid-close
  resumes confirmed, slightly laggy), but Dani prefers the current menu layout
  and suspends by closing the lid.

## 3c. Firmware (gap item 12) — what fwupd found, 2026-10-29

- **No LVFS updates for the BIOS** (`System Firmware`, Lenovo 82RB), the
  Samsung SSD (CL1QGXA7) or the Genesys USB hub. BIOS updates stay with Lenovo
  Vantage on Windows.
- **Pending, deliberately not installed:** Secure Boot certificate updates
  (KEK CA and UEFI CA 2011 → 2023, Microsoft's rollover before the 2011
  certificates expire in 2026) and the dbx revocation list. Secure Boot is off
  here, so none of them is enforced today, and Windows Update handles the
  rollover for Windows.
- **The UEFI variable store is nearly full:** the dbx update fails with "Not
  enough efivarfs space, requested 30.7 kB and got 23.7 kB". Don't write
  certificates into it from Linux on a whim; if Secure Boot is ever adopted,
  apply these at home, on mains power, after Windows has had its turn.

## 3d. Black screens at boot/login — leftovers from the 2026-11-12 investigation

The main cause (flatpak-remotes going online on every boot) is fixed and
merged; graphical.target is now reached at ~5.6s, offline or not.

- **USB device on hub port `3-2.1` sometimes doesn't respond**
  (`usbhid … error -110`, boots of 1 Nov and 3 Nov): adds ~20s to boot before
  the login screen. Hardware/dock side, not config. Unplugging/replugging the
  dock is the first thing to try if it keeps happening.
- **Unexplained:** 1 Nov 00:20, Reboot pressed on the login screen after ~3
  min with nothing in the journal. Dani recalls (not certain) a black screen
  where the greeter should have been; SDDM and X reported a normal start. Only
  worth chasing if a black greeter happens again - then note which display
  was black (laptop panel vs external).

## 4. danix-hp

- Still on the **scripted initrd** (`base.nix` pin). Must adopt systemd stage 1
  before the 26.11 bump, the same way legionix did.
- Never built or booted on 26.05: run `check-all` before its first rebuild.
- `hosts/danix-hp/hardware-configuration.nix` forces the disk to `/dev/vda`,
  while the README says the disk device is unset — reconcile before any
  install.
- `dns.nix` (parked) and `nix-ld.nix` are imported by legionix only.

## 5. Deadlines

- **NixOS 26.11** is due around the end of November 2026, and 26.05 stops
  getting updates about a month later. The scripted initrd is removed in
  26.11: remove the `base.nix` pin (needs danix-hp on systemd stage 1 first)
  and rehearse the bump with `check-all`.
- Gap item 6 (update cadence) is the planned way to stop falling behind:
  nixpkgs is locked at 2026-09-16.
- **Schedule (decided 2026-11-17):** Dani is away on mobile data / WG Wi-Fi
  until **2026-12-20**. Everything here and in section 1 (LUKS), section 2
  (resolved-dns), gap items 3/4/6 and danix-hp waits until then, at home with
  a fast connection. That leaves roughly ten days before 26.05 stops getting
  updates: prepare the 26.11 bump's code beforehand so that day is a build
  and a test, not a project.
- Until then, work only on things that need little download. (Git tag per
  generation: done 2026-11-17. Section 3, RT audio: checked, waits for 26.11.) Section 5b (boot look)
  is to be re-reasoned with Dani before any change.

## 5b. Boot look (idea from 2026-11-01, not started)

What can be changed safely between power-on and login, and what cannot:

- **Leave alone:** the LEGION firmware logo (only by reflashing firmware), the
  bootloader (systemd-boot is the recovery path - previous generations - and
  shares the ESP with Windows Boot Manager), and the Windows boot logo
  (HackBGRT-style tools replace EFI files on that shared ESP).
- **Option 1 - hide the boot menu** (`timeout = 0`): firmware logo straight
  into the splash. Space during boot brings the menu back; the power menu
  already has "reboot into Windows". Test that Space is actually caught on
  this firmware before relying on it.
- **Option 2 - Tokyo Night Plymouth theme**, replacing `bgrt` (which reuses
  the firmware logo, so it is already seamless). Best done after LUKS, since
  Plymouth then draws the passphrase prompt on every boot.
- Separate commits, `nixos-rebuild boot`, and never both at once: a broken
  splash is undone from the very menu option 1 hides.
- Windows lock/sign-in picture: set in Windows Settings, outside this repo.

## 5d. Reverie rice — merged 2026-11-22 (8634e2f); liquid glass — merged 2026-11-23 after Dani's "I love it now"

Second "craziest rice" experiment (2026-11-18). Unrelated to `rice/overdrive`
(which has its own entry on its own branch). One module,
`home/dani/wm/reverie.nix`, and a small Python daemon — since 2026-11-22 a
package of its own, `pkgs/reverie/` (`nix build .#reverie`) —
(GTK4 + gtk4-layer-shell + cairo) that draws surfaces
the compositor cannot. The module header lists every command.

**What is in it now**, all off or invisible until asked for: the **HUD**
(clock, day arc carrying today's focus history, gauges, every waybar module as
a chip, and a to-scale map of every workspace, built from live pictures of its
windows, that is also a switcher) on a blurred capture of the desktop; **zen** (stops waybar; title cards and the HUD
replace it); workspace **title cards** in three looks; a **spotlight** that
travels with focus; open/close **ripples**; **pulse** (workspaces as a
pentatonic scale; windows that fade when ignored); **undo** for the last
closed window; a focus **ledger**; and the **menu**, a deck of tiles that
holds every switch.

**Dropped after Dani's second review** (code reachable at `293c60a`):
- *strata*, the wallpaper generated from git history — "as a concept, strava
  is good, but its application... an autogenerated wallpaper kills the whole
  charm of a downloaded beautiful wallpaper. Maybe in some years this is more
  mature."
- *dream*, the flow-field screensaver — "a bit underwhelming ... I perhaps
  could go hunting for a good video on the internet for a screensaver".
  **Follow-up idea, not started:** a found video as the screensaver. `mpv` is
  already installed (`mpvpaper` is not); what is missing is the video (a
  download, so after 2026-12-20 or on a good connection) and one hypridle
  listener that plays it fullscreen and ends it on resume.
- the HUD's *glass lenses* — "looks odd and out of place". Liquid glass on
  real windows stays parked (below); this was an imitation on a screenshot.

**Try it without rebuilding:** `reverie try` (from the built store path)
starts the daemon and registers the binds for the session; `reverie demo`
walks through HUD, cards and spotlight and restores state; `reverie untry`
undoes it.

**Keys** (third arrangement; Dani asked for the swap and the new undo key):
`$mod+G` the HUD, pinned as a switcher · hold `$mod SHIFT+G` glance, the HUD
only while held · `$mod+U` undo close · `$mod+R` the menu. The binds use
Hyprland's `event` dispatcher instead of exec: the daemon reads the words off
the event socket, so nothing is forked per keypress. Five binds in all: four
presses (the glance one repeats, as a heartbeat) and one release.

**Dani's first review (2026-11-18)** — HUD: likes concept and elements, not
the style and font, wants everything waybar carries. Title cards: "simple but
genius", refine. Spotlight: good concept, unpolished. Strata/dream: not
understood. Keys: "kind of collide" (families and neighbours, not chords).
Answered the same day: desktop font, bar modules as chips, island card,
window-shaped spotlight pool, keys on unused families plus a menu.

**Dani's second review (2026-11-18, evening) and what changed:**
- *Keys* — swap glance and pin ("I will be pinning more often"); the reopen
  key "not the most mnemonic-friendly". Done, see above.
- *Reopen the last closed window* — "genius".
- *Menu* — likes the concept "a lot", but it should show every option at one
  glance and must not close on every change. Was walker's dmenu; now drawn by
  the daemon (`reverie/menu.py`): ten tiles in two rows along the bottom,
  lit when on, 1…0 / arrows / hjkl / mouse, stays open until dismissed.
- *HUD* — "includes all the info in the waybar, which I love, and now it
  looks a bit better". Three complaints, all acted on: the glass (removed);
  "the transparency of the content below the HUD doesn't look as good as it
  should" (the compositor's blur is one pass at size 3 — the backdrop is now
  a capture blurred hard and darkened, the lock screen's recipe); the hint
  said 1-9 for ten workspaces (now "1…0 workspaces 1-10"; the 0 key already
  worked).
- *Title cards* — "the element that I love the most", but "disappear a bit
  too soon" and "not convinced about its style". Hold 650 ms -> 1 s. The
  style has now missed twice without a stated reason, so there are three
  looks to compare live instead of a third guess: `bare` (default; the first
  version's idea in the desktop font), `island`, `banner`. **Open: which
  one, or what is wrong with all three.**
- *Spotlight* — likes the styling; "a bit too slow and it seems a bit
  unresponsive". The pool now moves like Hyprland's own window animation
  (exponential follower, tau read from the `windows` animation), starts on
  the event instead of 30 ms later, runs on the frame clock, and polls
  geometry at 20 Hz while anything changes.

**Dani's third review (2026-11-18, night) and what changed:**
- *Menu* — "I like the menu a lot." Nothing changed.
- *Title cards* — bare: "delicious right now ... they could be ruined and I
  like them a lot as they are". **Frozen. Do not restyle the bare card.**
  `island` and `banner` are still selectable and now unwanted; removing them
  (and their menu tile) is a clean-up waiting for a word from Dani.
- *HUD* — "better, without being visually stunning, and I don't know if we
  should strive for that or what." **Open question, Dani's to decide.** My
  recommendation, given in conversation: do not chase spectacle across the
  panel — it is read, not watched, and the one decorative attempt (the
  lenses) is what failed. If one push is wanted, give it a single hero: in
  pinned mode that is the workspace map, since switching is what it is used
  for.
- *Spotlight* — "moves better, but ... the animation could be better and more
  polished. Perhaps a bravest animation could help." Rebuilt as a handoff:
  the light reaches the new window first (~70 ms), the darkness follows over
  the old one (~330 ms), the pool breathes out as it lands and a glint runs
  round the window's border from where the light came in. **Not yet seen by
  Dani.**
- *Strata, dream* — "should be both removed, we can find other ideas that are
  more beautiful instead." They already were. Ideas offered in their place,
  none started: **rest** (when idle, the windows fade away and the chosen
  wallpaper is the screensaver, with the time set like the bare title card —
  no video needed, nothing locked); a **day set** (three or four photographs
  Dani picks, crossfaded by time of day; needs downloads).

**Dani's fourth round (2026-11-19, just after midnight) and what changed:**
- *"When transitioning from one workspace to other after having changed focus
  some times, it lags for about half a second."* The switch itself was never
  late (Hyprland announces it 12 ms after the key). Two full-monitor surfaces
  of this daemon were animating during the slide — the title card and the
  spotlight's sweep — each frame of each a 15 MB buffer; the daemon fell to
  ~40 frames a second for half a second and Hyprland presented 11-15 frames
  late per switch. Fixed: the card's surface is only as large as the card
  (same pixels, compared), and the spotlight treats a workspace switch as a
  cut (the pool is simply at the new window; only the glint plays). Same
  probe afterwards: 0-2 late frames, as with every effect off. **Dani has
  not yet confirmed it feels right.**
- *"I like the idea of improving the HUD with an improved workspace map ... as
  well as improving the HUD in general."* Done as a first pass: the workspace
  map is the hero (large cards in the middle, windows named by application
  and title, the selected card larger and lifted, left/right/enter to move
  and go), clock and gauges made small around it. **Not yet judged.**
- *Two spotlight bugs, reported right after:* the previous window's pool
  carried onto the next workspace, and sometimes no spotlight at all after a
  switch. One cause (the canvas was not redrawn when the pool jumped instead
  of travelling), fixed and covered by checks that compare what was painted
  with the focused window: 40 cases, all passing. **Not yet confirmed by
  Dani.**

**2026-11-19, afternoon — real thumbnails on the HUD's cards (commit
`bce450a`), asked for by Dani the night before:**
- Not workspace screenshots, as first planned. Hyprland hands out a single
  window's own buffer even when its workspace is not showing (`grim -T`), so
  every window is photographed when the panel opens and the card is put
  together from those (`reverie/thumbs.py`). Nothing is cached from an
  earlier visit, so nothing is stale, and neither the spotlight's dimming,
  the fade, nor a title card can be in the picture.
- While the panel stays pinned, the windows on the showing workspace are
  retaken every two seconds; a window that opens or changes size gets a new
  picture; one with no picture (yet) is the drawn pane it was before.
- Measured and seen on the real compositor: first pictures on the cards
  ~125 ms after the command; a frame of the panel 6 ms; windows on a hidden
  workspace captured correctly; a window closing and one opening while
  pinned followed within the two-second reading; a window at 30 % opacity
  photographed at full strength. Daemon memory 55-90 MB anonymous across
  repeated opens (it was 240-320 MB before freed capture buffers were handed
  back with `malloc_trim`).
- **Not judged by Dani yet.** In particular: the name and title are still
  written on each window, over a shade at its top edge — they may now be
  more than the picture needs; and a window untouched for ten minutes is
  darkened by up to a quarter (the old "attention heat").
- **Not verified:** XWayland windows, fullscreen windows, floating windows
  overlapping others, more than three windows at once, a second monitor, a
  scaled monitor (pictures are kept at layout-pixel size, so they would be
  soft there). Transparent windows come out on black rather than on the
  wallpaper. The space between windows and an empty workspace's card are
  still the plain island, not the wallpaper.
- This session started after a reboot: the daemon and the session binds were
  gone (nothing in git was), and were brought back with `reverie try`.

**2026-11-19, night — Dani's fifth round** ("I like a lot what we have
accomplished"), and what changed:
- *"I don't want any auto fading the screen when it is not being used ... it
  is messing up some of the transparencies and it looks unpolished."* That
  was reverie's own **fade** (windows lose opacity after a minute without
  focus); the system has no idle dimming or locking at all (hypridle runs
  with no listeners). Switched off, and it stays off across restarts. **The
  code and its menu tile are still there**: removing them changes the menu's
  grid, so it waits for Dani's word. The HUD's darkening of long-untouched
  windows' pictures is a different thing and is still on.
- *Where do the thumbnails' screenshots go?* Nowhere: they are never files.
  grim writes each picture to a pipe, the daemon keeps a small copy in its
  own memory, replaces it when a newer one is taken, drops it when the
  window closes, and all of it is gone when the daemon stops.
- *Spotlight "can be improved further if it can be smoother"* — commit
  `f88d3a3`. It was drawing ~42 frames a second (21-22 in half a second,
  waits of 17-28 ms): the daemon's software renderer cannot repaint a whole
  monitor every frame. The spotlight is now its own program
  (`reverie/spot.py`) on GTK's GL renderer, started when the spotlight is
  switched on and gone when it is off: 91 frames in 553 ms (165 a second),
  longest wait 7-8 ms. Same handoff and timings. 22 live checks pass
  (handoffs, workspace switches incl. to and from empty, rapid switches,
  floating, maximise, close, menu lit, on/off/on). **Costs:** ~240 MB
  resident while the spotlight is on (the GL driver), nothing when off; the
  light takes ~0.3 s longer to appear when switched on (a process starts).
  **Not judged by Dani.** Not tested: two monitors.
- *"Could the HUD be more spectacular? We can always revert."* — commit
  `131a20a`, one commit so `git revert 131a20a` is the way back. Cards sweep
  in; the selected card sits in a pool of light and the backdrop darkens to
  its corners; the wallpaper is under the windows on each card; going to a
  workspace, its card comes forward to fill the screen. Frame cost 8-9 ms at
  rest (was 6), 12 entering, 17-21 while a card comes forward. Seen on the
  real screen: the entrance, and the zoom into the current workspace by a
  real key press (panel gone and unmapped afterwards). **Only rendered
  offscreen:** the zoom into a different workspace (it happens over
  Hyprland's own slide and the title card, which I have not watched
  together). **Not judged by Dani**; the light may be too faint to notice.
- Dani was using the machine during this session (Firefox on workspace 3):
  my live tests switched workspaces and took the keyboard for a second a few
  times. Offscreen first, and ask, when that is the case.

**2026-11-20, small hours — Dani's sixth round** ("I like it A LOT. But I
think there is room still for making it spectacular and jaw-dropping"), and
what changed:
- *Bug: "when you go from an empty workspace to another with a spotlighted
  window, the card is affected visually by the shadow and the spotlight."*
  Commit `d1bcd07`. The spotlight's overlay and the title card were on the
  same layer, where the compositor stacks by who mapped last; the spotlight
  unmaps when nothing is dimmed, so arriving from an empty workspace it was
  mapped again after the card and lay over it (`hyprctl layers` showed it).
  The spotlight is now on the `top` layer, under everything reverie puts on
  `overlay`. Checked on the real compositor with the card straddling the
  pool's edge. **Not confirmed by Dani.** Side effect, by design: the menu
  and the HUD can no longer be dimmed by the spotlight either; a bar that is
  (re)started while the spotlight is showing sits above it until the
  spotlight is next mapped.
- *The HUD, "spectacular and jaw-dropping"* — commits `9181b2e`, `98ac731`:
  the panel as a second program drawing on the graphics card
  (`reverie/stage.py`), in which the screen itself receded to become a card
  on a carousel of workspaces in perspective. **Rejected by Dani on
  2026-11-22 and reverted (`343a42d`)** — see the seventh round below.
- *Still waiting from the fifth round:* whether the Fade tile goes from the
  menu (asked, not answered).

**2026-11-22 — Dani's seventh round:** *"the idea of improving the HUD with
some sort of carousel was good but the execution looks terribly buggy and
quite horrible to look at. I would prefer to keep the previous version of the
HUD rather than the current one."*
- **Done:** the carousel is reverted (`343a42d`). `stage.py`, `capture.py`,
  `host.py`, the `hud stage` switch and the `reverie-stage` layer rule are
  gone; everything under `home/` is byte for byte what it was at `d1bcd07`
  and builds to the same store path. The HUD is again the daemon's own panel
  — the one of the fifth round (`131a20a`): cards in a flat row, sweep in,
  light behind the selection, wallpaper in the cards, zoom into the chosen
  workspace. Seen on the real compositor after the revert. The title-card
  fix and the GL spotlight stay.
- **What the HUD is to Dani now:** the fifth-round panel, which he likes
  "A LOT". Leave it alone unless he asks.
- **Parked, as an idea only:** a carousel of workspaces ("the idea ... was
  good"). The code at `98ac731` is NOT the way to do it and should not be
  brought back as it is. **Not known:** what exactly looked buggy and
  horrible — Dani did not say and was not pressed. Whoever tries again
  should ask first, and show small steps on the real screen before building
  the whole.
- **What went wrong on my side, for the record:** I reported it as tested —
  every key and click pressed for real, frame timings, a pixel-exact first
  frame — and none of that is "does it look right to the person using it".
  I could only look at stills, and said so in passing; I should have handed
  it over as an experiment to be judged before making it the default, as
  `rice/reverie`'s own history (strata, dream, the lenses) had already
  taught.
- Worth keeping from that work, should anything need it again (all in the
  history at `98ac731`): Hyprland hands over a capture of the screen in
  ~15 ms and of a window in ~5 if asked directly (wlr-screencopy,
  hyprland-toplevel-export) instead of through grim; GTK's GL renderer can
  render any frame offscreen for inspection
  (`Gsk.GLRenderer().realize_for_display` + `render_texture`); the RTX 3070
  idles at a tenth of its clock and needs ~0.2 s of load to leave it, so
  anything drawn on it is slow for its first frames after an idle spell.
- Noticed in passing on the HUD's own chips, unrelated to reverie:
  `restic-backups-remote.service` is in the failed state ("backup failed").

**2026-11-22, later — Dani's eighth round**, four things:
- *"I like how the HUD looks now, I would only want to improve it a bit
  further when it is possible, when I have more time."* **Parked: small
  improvements to the HUD, at Dani's initiative.** Nothing to do until he
  says what.
- *"we could commit that and apply the changes. My only concern is that ...
  they don't look Nix-y at all ... like some Python scripts put together."*
  He is right, and it was said to him so: 320 lines of Nix packaging and
  wiring ~5,000 lines of Python. What the Nix does: the Python environment
  from nixpkgs, the colours from `theme/palette.nix`, the shellchecked
  wrapper, the systemd user service, the binds, the layer rules.
  - **Done (`58fc6b4`):** the build now byte-compiles and imports every
    module, so a broken daemon fails the build instead of the rebuilt
    system. Tried with a bad import: the build fails.
  - **Proposed, waiting for Dani's word** (no change in behaviour): split
    `reverie.nix` into a package (`nix build .#reverie`, no `packages`
    output exists in the flake today) and a small module; an `enable`
    option instead of being on for every host that imports the WM config;
    removing what he has turned down (the Fade switch; the `island` and
    `banner` title cards).
  - **To be said plainly at every bump:** this is software the repo now
    owns. Hyprland's event socket, `hyprctl -j` fields and layer-rule syntax
    are what it stands on; the 26.11 bump (after 2026-12-20) is the first
    time that will be tested.
  - **Applying it** has never happened: the systemd unit, the declared
    binds and the idle listener have only ever existed in the file. First
    `reverie untry` (or two daemons answer every key), then
    `sudo nixos-rebuild test --flake .#legionix` from this branch, then
    look; `switch` and the merge into master only after that.
- *The parked ideas, brought back for review* (to be developed once reverie
  is applied and merged, each on its own branch off master):
  1. **Noir focus mode** (liked "quite a lot") — exists as a screen shader on
     `rice/overdrive`; porting it is a small module and a switch. No
     downloads.
  2. **Glow ring** — the screen edge as an ambient channel, the "ping/alarm
     shown more beautifully". Needs its sources decided first (long
     commands, Claude Code, recording/mic, a failed backup, battery). No
     downloads.
  3. **Liquid glass** — see below.
  4. *From reverie's own list:* a carousel of workspaces (idea liked,
     execution rejected); a **day set** of photographs by time of day
     (needs the photographs); **rest** and a **found video** as
     screensaver — both are things that happen when the machine is idle,
     which Dani has since said he does not want; treat as dropped unless he
     says otherwise.
  5. *Older, unrelated to the rice:* the boot look (section 5b).
- *Liquid glass: "do you think we could implement it graciously? ... should
  we put this texture in all the menus/HUD?"* Looked into on 2026-11-22:
  - The plugin is `hyprglass` (github.com/hyprnux/hyprglass, BSD-3): blur,
    edge refraction, chromatic aberration and specular highlights on
    transparent windows **and, opt-in by namespace, on layer surfaces**
    (bars, menus, notifications). It is not in the pinned nixpkgs
    (`hyprlandPlugins` has thirteen others); it would be a
    `mkHyprlandPlugin` derivation from its source.
  - **Versions:** each release targets one Hyprland. Ours is 0.55.4, which
    only v0.6.4 (June 2026) supports; the current v1.2.0 targets 0.57.2 and
    has five months of fixes, among them "a huge window, bar or menu no
    longer crashes Hyprland". Its layer support "hooks into Hyprland's
    internal render pipeline ... may break across Hyprland updates".
  - **Download:** building any plugin against the installed Hyprland needs
    32 store paths, 104.8 MiB (measured with a dry run; nothing fetched),
    plus the plugin's source.
  - **Recommendation given to Dani:** do it after 2026-12-20, right after
    the 26.11 bump, with the plugin version that matches the Hyprland that
    bump brings — not now with a five-month-old one on a slow connection.
    As an option that is off until he has looked at it, on one surface
    first. What he liked on `rice/overdrive` was `drift`'s full-screen
    imitation; the real thing bends what is behind each surface's edge and
    may or may not be what he pictured.
  - **Where it would go:** on what floats over live content — windows, the
    bar's islands, the launcher, notifications, reverie's menu deck. **Not
    inside the HUD:** the HUD paints its own backdrop, so there is nothing
    behind its cards for glass to bend, and drawing it anyway is the
    imitation he already turned down (the lenses). **Not on the bare title
    card** (frozen).
  - Not checked: whether v0.6.4 has layer support at all; how it behaves
    with NVIDIA, with the spotlight's overlay, and under a fullscreen game.

**2026-11-22, evening — Dani's answers, and what was done with them:**
- *The Nix tidy: yes.* Done, two commits, no change to what runs:
  - `65386d8` — the program is `pkgs/reverie/` (`package.nix`, the keys and
    layer rules as data in `hyprland.nix`, the Python in `src/`, moved with
    history); `home/dani/wm/reverie.nix` is only configuration; the flake has
    its first `packages` output (`nix build .#reverie`,
    `nix run .#reverie -- try`). Checked: legionix's and danix-hp's
    generated `hyprland.conf` were the same store paths as before, the
    wrapper and sources identical apart from store hashes, `.#reverie` is
    the derivation legionix installs, statix and deadnix clean.
  - `837eaf1` — `services.reverie.enable` (and `.package`); only
    `hosts/legionix/desktop.nix` sets it. danix-hp no longer gets the
    command, service, listener or binds it had never been rebuilt with.
- *Remove the Fade switch and the `island`/`banner` cards: no.* They stay,
  as they are. Do not ask again.
- *Noir first, then the glow ring, after the merge: yes.*
- *Liquid glass after the 26.11 bump: no* — "can't we install hyprglass
  0.57.2? I would really like to use it as soon as possible." Looked into
  further:
  - The current hyprglass (v1.2.0) only runs on Hyprland 0.57.2. That
    Hyprland is in the nixpkgs-unstable this flake already has locked, but
    **0.57 removed the `hyprland.conf` format: Lua is the only config.**
    Moving to it means rewriting the whole Hyprland configuration in Lua
    (92 binds and 19 rules in today's generated file, spread over 9 Nix
    files), which the Home Manager release in use cannot generate, checking
    everything reverie asks of Hyprland again, and 264 MiB of downloads
    (115 for Hyprland, the rest to build a plugin against it; dry runs).
    That is the 26.11 migration, not a quick step.
  - What can be had now is **hyprglass v0.6.4**, whose own pin names
    exactly this machine's Hyprland commit (`a0136d8`): nine C++ files and
    a Makefile, configured in the old config format
    (`plugin:hyprglass { … }`), glass on windows and — by listing their
    namespaces — on layer surfaces, presets `subtle`, `clear`, `glass`,
    `high_contrast`. Cost: ~105 MiB of build dependencies plus its source,
    and it is five months behind: two crash fixes came later (one on
    unloading, one for "a huge window, bar or menu"). A plugin that crashes
    takes the session with it.
  - **Dani: "now bring hyprglass v0.6.4".** Done on `feat/liquid-glass`
    (off master), nothing loaded into his session yet:
    - `fddc2c0` — `pkgs/hyprglass/package.nix`, `nix build .#hyprglass`
      (mkHyprlandPlugin, so always against the hosts' Hyprland).
    - `b5644af` — `pkgs/hyprglass/trial.nix`, the `glass` command:
      `nix run .#glass -- on [preset]`, `preset <name>`, `off`, `status`.
      Runtime only; `off`, a logout or a reboot removes all of it.
  - **What a nested Hyprland showed** (the system's binary, this desktop's
    `general`/`decoration` blocks, the real wallpaper, Alacritty, a copy of
    the bar — nothing of the real session touched):
    - It loads, draws, unloads and reloads without a crash; so does layer
      glass on the bar.
    - **Hyprland's own blur covers it completely.** With blur on, loading
      the plugin changes not one pixel. Blur has to be off for the window
      (`no_blur true` rule / `setprop … no_blur 1`); the layers can keep it.
    - **It only shows through transparency, and this desktop has little:**
      windows are 88–94 % opaque, the bar's islands nearly solid. On the
      windows as they are, every preset looks alike. The trial therefore
      gives the open Alacritty terminals a see-through background
      (`alacritty msg config window.opacity=0.55`; text stays solid).
      **For glass to stay, something has to become translucent on purpose**
      — the terminal's background, and whichever of bar / launcher /
      notifications / reverie's menu should carry it. That is a theming
      decision for Dani, after he has seen the trial.
    - Presets: `glass` is the liquid one (wide refraction band with colour
      fringes at the edges — may be too much for the palette), `subtle` and
      `default` frosted, `clear` a plain plate, `high_contrast` dark.
    - A change of preset repaints only partly until the windows are
      touched; the command re-sets the window property to force it.
    - The plugin hooks Hyprland's layer rendering as soon as it is loaded,
      whether layer glass is on or not.
  - **Not tested:** the real session — on the NVIDIA machine's own outputs,
    with reverie's spotlight/HUD/cards on screen, with a game, and what it
    costs per frame. A plugin crash ends the session.
  - **Dani tried the trial (2026-11-22):** "for sure they are a treat to
    the eyes", not sure which look he likes most; wants "as much glass as
    reasonably possible", as proper switches, and suggested the two glass
    switches take the place of reverie's Font and Demo tiles so the deck
    stays symmetrical. Done, three commits, nothing applied yet:
    - `48c3172` — `programs.glass.enable` (`home/dani/wm/glass.nix`,
      legionix) + `glass on|off|toggle|look liquid|frosted|clear|next`.
      The choice is runtime state (`~/.local/state/theme/glass.json`);
      the command writes `glass.conf`, which the Hyprland config sources
      last and which declares the plugin when on — so Hyprland loads and
      unloads it itself, and a reload or a login cannot lose it — and
      `glass.toml`, which Alacritty imports (background 0.65 while on).
      The trial command (`trial.nix`) is gone; this replaced it.
    - `d12188b` — the bar's three islands and the swayosd pill: their
      background is `programs.glass.islandBackground` (0.85 off, 0.30 on,
      from `glass.css`), and the plugin's layer glass is on for them.
    - `274ce47` — reverie's menu: tile 7 Glass, tile 8 Glass look, where
      Font and Demo were (both still commands). Only when built with
      `glass`.
  - **How it was tested:** all of it in a nested Hyprland running the
    real generated config, with its own state directory, a copy of the
    bar and a second reverie daemon. The complete legionix system builds
    from the branch. **Never run in the real session**, and the swayosd
    pill has not been seen on screen at all (its stylesheet parses).
  - **Known limits of what is there:**
    - One look for everything. The idea of a refracting look for small
      floating pieces and a frosted one behind text is not built.
    - Only Alacritty turns see-through; every other window stays 88–94 %
      solid and shows almost no glass. That is as intended.
    - With glass on, the terminal breaks the "Hyprland owns all window
      opacity" rule (`shell/alacritty.nix`) on purpose.
    - Nothing switches glass off for a game. Fullscreen windows draw no
      decorations, so the glass itself should cost nothing there, but the
      plugin's hook stays in the render path and none of this is
      measured. A GameMode hook calling `glass off` is the obvious fix if
      it shows in the eFootball numbers.
    - If the plugin crashes Hyprland: it restarts in safe mode (no config,
      so no plugin). `glass off` from there or a TTY, then load the
      config. Read from the binary's own text, never tried.
    - A rebuild that changes Hyprland builds a new plugin; the running
      (old) Hyprland will refuse it until the next login.
  - **Dani applied it (2026-11-22): "It looks great now. Do the next
    ones."** (Super+R was dead for a moment first — my test compositor had
    overwritten the session's display variables in systemd; fixed, and the
    tests now run sealed off in their own runtime directory.) Done since,
    committed (applied since):
    - `f86ccd3` — the launcher (walker): its box is `popup_bg` by name,
      0.90 off, 0.50 on, 0.72 under the clear look
      (`programs.glass.popupAlpha`/`popupAlphaClear`); the plugin gets the
      `walker` namespace with a mask threshold of 0.4 so the box's shadow
      gets no glass. Launcher, window switcher, emoji, clipboard, the
      Super+S board and the wallpaper picker share the box; the power and
      capture menus keep their own 0.97 and stay solid, on purpose.
    - `291e4e4` — reverie's menu deck: namespace `reverie-menu`, and the
      deck paints itself 0.50 (0.72 under clear) when glass is on.
    - `c3f750b` — fix: the command lost track of which state files it had
      changed (writes through a pipe), so walker was not restarted when
      the look crossed into or out of clear; and `glass refresh` (run at
      every activation) now reloads Hyprland when the rules file changed,
      so a rebuild that adds a surface takes effect without a toggle.
  - **How these were tested:** the launcher with a stand-in layer surface
    named `walker` wearing the real new stylesheet (the real walker will
    not run as a second copy in a nested Hyprland — it panics there with
    the old stylesheet too); the deck with a second reverie daemon. All
    four launcher stylesheets parse under GTK4. **The real launcher has
    not been seen with glass.**
  - **Known limits added by these:**
    - The plugin samples what is behind a layer once and keeps it until a
      window is focused or moved or the layer reopens. Stepping the look
      changes windows at once; the bar's islands and an open deck catch
      up at the next change of focus / the next opening.
    - If only the colours in `glass.css` change with a new version of the
      command (not the units that read them), waybar and swayosd keep the
      old ones until the next toggle.
  - **Dani, after seeing launcher and deck (2026-11-22, night):** they
    "should be quite darker than the normal selected glass, perhaps a
    separate type of glass"; a fullscreen window "completely ignores the
    liquid glass look and it looks see-through completely"; and "I wonder
    if the HUD couldn't get a glass look that doesn't look bad." Done,
    committed (applied since):
    - `5f998c8` — a glass of their own for the panels that are read: the
      plugin's preset per layer namespace, `menu` (its subtle glass,
      blur 1.6, brightness 0.55) for `walker` and `reverie-menu`, whatever
      look is chosen for the rest; box and deck 0.60 solid over it. The
      clear-look special case (`popupAlphaClear`, the deck's 0.72) is gone
      again, since this glass always blurs.
    - `9dda57a` — fullscreen: Hyprland draws no decorations for a truly
      fullscreen window and the plugin's glass is one, so with blur off a
      see-through terminal was a hole onto the wallpaper. Real fullscreen
      (`fullscreen_state_internal 2`) gets Hyprland's blur back. It is
      frosted, not glass, and brighter than the windowed terminal (blur
      cannot dim). **If Dani would rather have fullscreen solid:**
      `force_rgbx true` on the same match instead (the terminal's
      background then comes out darker than its palette colour).
      Oddity found on the way: only a terminal opened while glass is on is
      see-through in fullscreen; one opened before stays solid there.
  - **The HUD and glass.** First three experiments with the HUD's one
    surface handed to the plugin (glass as its backdrop; glass only behind
    cards and chips; backdrop glass with refraction): none read as glass.
    Why, from the plugin's source: on a layer the glass is one rectangle,
    the surface's own box, and the surface's alpha only cuts holes in it —
    and the HUD is opaque pictures and thin type on one dark surface.
    Dani: "Yes, prototype the two-layer HUD".
    - **Built (`46a4b29`), applied, and rejected.** A glass tray under
      the workspace cards and glass pills under the chips, on surfaces of
      their own, once the panel had arrived. Dani: "I like the glass
      features but I don't like the HUD look now." Reverted (`355d0c0`).
      Do not bring pieces of glass back onto the panel.
    - **What he asked for instead, built `5927ee9`, applied 2026-11-23:**
      "a dark version of liquid glass with the current wallpaper without
      showing what apps are open below the HUD." With glass on, the
      panel's backdrop is that monitor's wallpaper — darkened, and as far
      out of focus as the chosen look (sharp under clear, soft under
      liquid, hard under frosted) — instead of the desktop out of focus.
      Painted by the panel itself (the plugin can only put behind a
      surface what is behind it: the windows). The picture is kept and
      made ahead, so the panel comes up on it at once.
      `reverie hud glass off` goes back to the capture; without glass it
      is the capture anyway. The darkness per look is `PANE` in
      `src/hud.py`, three numbers to turn if he wants it darker or
      lighter.
  - **Fullscreen and the selected look, built `b59616c`, applied
    2026-11-23.** Dani: "I would like the full-screen apps to apply also the
    selected liquid glass style, now they don't have that at all" (the
    blur given back in `9dda57a` is not the look). Real glass for a
    fullscreen window after all, by another road: while a see-through
    window (Alacritty) is fullscreen, reverie maps an all-but-empty
    surface on the `background` layer above the wallpaper
    (`src/under.py`), and the plugin makes the chosen glass of it.
    `programs.glass.fullscreen` = "underlay" where reverie is enabled,
    "blur" elsewhere. Not tested on two monitors. Nothing is put under a
    game or any other opaque fullscreen window.
  - **Housekeeping noticed 2026-11-23:** `nh-clean` runs weekly (Monday
    00:00) and removes build-only tools; the first rebuild after it
    downloads about 4 MiB (ShellCheck, stdenv hooks) and regenerates a
    couple of hundred small files. Already done for this branch's
    current state.
  - **Second round the same day: Dani applied it and reported five
    things.** Four were faults, fixed one commit each; all measured and
    seen in the sealed nested Hyprland only.
    - *"When I make an app fullscreen, the glass disappears for a
      moment."* The sheet took 35 ms to arrive and 250 to fade in. Now at
      once and whole: 1-5 ms, `no_anim` (`85ef125`).
    - *"A difference between the colour intensity"* between fullscreen
      and windowed. Hyprland's `fullscreen_opacity` (1.0) against the
      0.94 of a window. The see-through windows keep 0.94 in fullscreen
      while glass is on; which windows those are is one option now,
      `programs.glass.windows`, and it includes the scratchpad terminals
      (`995f300`).
    - *Fullscreen glass "doesn't change to its selected glass mode right
      away, or it doesn't change wallpapers".* The plugin keeps its sample
      of what is behind a layer. Reverie now makes it sample again (the
      sheet changes size by a pixel) after every config reload and through
      a wallpaper change, which it learns of by watching
      `~/.local/state/wallpaper/current` (`dcd95fa`). The HUD's backdrop is
      remade then too, so the "old picture for a moment" limit is gone.
    - *The Super+R menu "remains as a gray box that takes almost a second
      to disappear".* The deck faded itself and the dark glass behind it
      could not follow. On glass it unmaps at once and the compositor does
      the fade (`5adbbb5`).
    - *"Could the HUD benefit from adding liquid glass … on the background
      wallpaper, and only on the wallpaper?"* Answered with a picture;
      Dani: "Add the real glass HUD as a third choice, you could add it to
      the Reverie menu … instead of the Fade option." **Built** (`575d548`,
      `29834b0`): `reverie hud look glass|wallpaper|
      desktop`, and a **HUD look** tile where Fade was (Fade was unwanted
      since 2026-11-20; `reverie pulse fade on` still works). Under
      `glass` the panel is see-through over a surface of its own that
      shows only the wallpaper, and the plugin makes the chosen look of
      it. Default stays `wallpaper`. Glass and Glass look moved one key
      left (6, 7; HUD look is 8). Darkness per look: `WALL` in
      `src/hud.py`.
    - **Applied, and "they seem the same to me, and I can't see the
      wallpaper at all".** His wallpaper is a WebP and the daemon could
      not read WebP (gdk-pixbuf loaders; I had only tried JPEG and PNG,
      from a shell), so `glass` and `wallpaper` both fell back silently
      to `desktop` — since `5927ee9`. Fixed `8eb5bea`: the wrapper names a
      loader list with WebP in it, and an unreadable wallpaper is logged.
      **From now on: test with his current wallpaper and with the
      service's environment (`env -i`, its PATH), not mine.**
    - **"If now every type of file can be read, we are ready to wrap it
      up."** It was not: nine of twenty formats tried were refused (SVG,
      AVIF, JPEG XL, HEIC, QOI, DDS, EXR, HDR, farbfeld), and `wall-set`
      takes any file. Now (`41a0490`) what GdkPixbuf refuses goes to
      ImageMagick, named in the wrapper; all twenty read in the
      service's bare environment, and the whole library. *Not done:*
      asking awww which of those it can show, and opening the HUD over
      one — the test compositor would not start that evening ("GBM:
      Failed to allocate a GBM buffer: bo null", cause not looked for;
      it had worked three hours earlier).
  - **"I wouldn't mind to add it to all the appropriate things."**
    - *Done:* notifications, on the dark `menu` glass, 0.60 solid
      (`1e6ffbb`); they follow the switch without a restart.
    - *Done at his word ("add glass to the power and capture menus too",
      `3e64da6`):* their box is 0.70 solid while glass is on, 0.97 as
      before otherwise (`confirm_bg`, `programs.glass.confirmAlpha`). Not
      seen with the real launcher; seen with a stand-in.
    - *Offered, not done:* the `island` and `banner` title cards.
    - *Not appropriate:* browser, editor and other windows that are read
      all day; the bare title card (frozen); spotlight, mouse grid,
      screenshot tools; tooltips and context menus (the plugin does not
      do popups). *Not possible:* lock screen, login screen.
  - **Known limits now:** nothing switches glass off for games; the
    underlay is untested on two monitors; following a wallpaper change
    costs about 0.4 s of CPU in the daemon at 1280x800 (more on the real
    screen), only while a terminal is fullscreen; the real launcher and
    the volume pill have still not been seen with glass by me.
  - **Dani's verdict, 2026-11-23, on the rebuilt branch (`6e6a45e`):
    "I love it now."** `feat/liquid-glass` is merged into master (not
    pushed). What he ran was `nixos-rebuild test`; the last fix
    (`41a0490`, wallpaper formats) came after it. **Still his to run:**
    `sudo nixos-rebuild switch --flake .#legionix` (makes it the boot
    default and brings that fix; glass can stay on), and `git push`.
- *Applying reverie:* Dani ran `nixos-rebuild test` on 2026-11-22 and
  confirmed "all the keybindings work as intended"; `rice/reverie` is merged
  into master (8634e2f, not pushed). **The running system is not yet the
  boot default** — still to be run by Dani:
  `sudo nixos-rebuild switch --flake .#legionix`.
  (zen is on in reverie's saved state, which is why the bar is stopped.)

**Tested (against the built package, nothing rebuilt):**
- Builds offline (shellcheck included); all three hosts evaluate; statix and
  deadnix clean on `reverie.nix`; no literal colours outside the palette.
  `keybinds-menu` was built from the branch and run against the live binds
  with a stub walker: undo is filed under Windows, the others under System,
  release binds are not listed.
- **Real input.** `/dev/uinput` is writable by Dani's user, so a virtual
  keyboard and mouse pressed and clicked everything through the kernel, keyd
  and Hyprland (scratchpad `keys.py`): pin, and that its own release does not
  close it; the glance with every order of letting go (G first: gone at once;
  a 300 ms peek let go in a bad order: ~520 ms; after the first repeat:
  ~225 ms; held two seconds: never cut short); the menu by arrows, hjkl, tab,
  a digit, a click on a tile, a click beside the deck, the menu key again and
  esc; the pinned HUD by a number key and by a click.
- What that taught about Hyprland 0.55: once any other key of a chord is
  released, release binds on the keys still held do not fire at all (five
  probe binds, five orders). Only "G first" can be caught by a release bind;
  the repeating bind's heartbeat covers the rest, and is remembered across
  restarts.
- Compositor frame pacing through a workspace switch, counted by an
  independent 4x4 px probe surface (scratchpad `probe.py`) over the same
  sequence each time: previous build 11-15 late frames switching back to a
  tiled workspace, this build 0-2, every effect off 0-3.
- The new HUD with real keys: pin, left/right keep it open and move the
  selection, enter goes and closes, Super+G closes a pinned panel and it
  stays closed (it used to reopen), the glance still works. A frame of it
  draws in 5-6 ms (was 23) with text layouts cached.
- **Seen on the real compositor:** the HUD's new backdrop; the menu deck with
  the spotlight on (the deck stays lit, the pools merge); the bare title
  card; the spotlight handoff grabbed twice mid-flight, matching the
  offscreen frame-by-frame render; the spotlight closing in when switched on.
- HUD: first frame 8-9 ms after the command (was 70-90: a blocking battery
  read before mapping), blurred backdrop in at ~100 ms.
- Spotlight cost per focus change, measured over rounds of real focus changes
  on three tiled terminals: 188 ms of CPU in the daemon and 189 ms in
  Hyprland, over about half a second (first cut of the handoff: 265 + 340).
  At rest with the spotlight on: 0.3-0.7 % of one core, ~115 MB resident.

**Not done / not verified:**
- **Nothing was rebuilt.** The systemd unit, the declared binds and the
  hypridle listener have never run; only `reverie try` has. Until a rebuild
  the ledger overcounts the focused window while you are away.
- **Whether the handoff looks good is not something I can settle.** Stills
  and timings say it does what it was designed to do; "polished" and "brave
  enough" are Dani's to judge, in motion. The glint in particular is a thin
  line and may be too quiet, or too much.
- **`island` and `banner` card looks, and ripples, were not looked at on the
  real compositor** (offscreen renders only, and the looks are unwanted now).
- **Bar chips not seen in every state** (no media player, no tray app,
  bluetooth off, nothing failing at test time). **Sound was not heard by
  me.** **Single monitor only**: the per-monitor spotlight overlays, the
  glint strips on a second monitor, and HUD/cards following focus across
  monitors have never run with two. **The focus arc has one day of data.**
- **Known limits, by design or not fixed:**
  - the HUD and the menu are still full-monitor surfaces (they need to be:
    one is a backdrop, the other catches clicks beside the deck); they do not
    animate during a workspace switch, which is when that mattered;
  - a focus change with the spotlight on costs about a third of a core in
    each of the daemon and the compositor for half a second. All the Python
    in it is 30 ms; the rest is GTK's software renderer carrying the whole
    window's buffer forward every frame. The real fix is to stop having one
    full-screen surface (per-tile render nodes, or letting the compositor
    draw the glint as a border animation); not done;
  - with `input:follow_mouse = 1` every window the pointer crosses is a focus
    change, so sweeping the mouse across the screen plays a handoff per
    window;
  - a glance let go in a bad order before the keyboard's repeat delay
    (600 ms) has passed stays up until that delay runs out;
  - the HUD's backdrop is a capture, so whatever moves behind the panel is
    frozen while it is up; the capture is taken a few ms after the panel
    starts fading in, which the blur hides;
  - the bare title card has no blur under it (a blur that stops at the edge
    of a soft shade shows as a ring), so over a bright, busy window it is the
    least legible of the three;
  - `undo` re-runs the closed window's command line: terminals come back
    without their session, sandboxed/Flatpak apps may not come back at all,
    and a one-shot command would be run again;
  - `hyprland.nix` has one statix warning (useless parentheses, line 718)
    that is also on master;
  - the hypridle listener (180 s) is new idle behaviour for this machine: it
    only notifies the daemon, it locks and dims nothing.
- **Candidates for the daily rice**, by Dani's three reviews: the bare title
  card ("delicious", frozen), the menu ("I like the menu a lot"), `undo`
  ("genius"), the HUD (carrying the bar: "love"; look: "better, without
  being visually stunning", since rebuilt round the workspace map and
  unjudged), the spotlight (styling liked; motion on its third version,
  unjudged). Not yet commented on: zen, ripples, sound, fade.

**Parked from `rice/overdrive`** (Dani, 2026-11-18: store, implement later
once more ideas have been collected — not now):
1. *Noir focus mode* — the whole screen monochrome except the warm attention
   band, as a toggle.
2. *Glow ring* — the screen edge as an ambient channel: position = source,
   colour = severity, steady glow for states, one swell for events.
3. *Liquid glass on windows* — **done**, 2026-11-23 (`pkgs/hyprglass`, the
   `glass` command, above; it did not have to wait for 26.11). (Reverie's HUD had cairo lenses imitating
   this on a screenshot; Dani found them "odd and out of place" and they were
   removed. That verdict is about the imitation, not about glass on windows.)

## 6. VM rehearsal notes (danixos-vm)

- libvirt snapshots do not work for this VM ("internal snapshots of a VM with
  pflash based firmware require QCOW2 nvram format").
- Deploying to the running VM: copy the repo in (`tar … | vmsys '… tar -xf -'`)
  and run `nixos-rebuild boot` inside it. Pushing a closure from legionix fails
  because the VM only trusts root for unsigned paths.
- Its system is ~30 GB (it imports gaming, docker, …), which is why
  reinstalls are slow on weak networks.
- The installer ISO gets a new SSH host key every boot: use
  `-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no` for it only.

## 7. Gap study — status of the 17 items

| # | Item | Status |
|---|---|---|
| 1 | Full-disk encryption | 1a–1c merged; paused (section 1) |
| 2 | Correct time + DNS not depending on Tailscale | branch `feat/resolved-dns`, parked (section 2) |
| 3 | Local btrfs snapshots (snapper on a `/home` subvolume; Steam on its own) | not started — wants the migration-day layout |
| 4 | Second, independent backup copy + system-state paths | not started |
| 5 | Health alarms (smartd → notifications, btrfs scrub, failed units, backup age) | **merged** |
| 6 | Update cadence (local weekly update + `check-all` timer, `configurationRevision`) | not started |
| 7 | nix-ld | **merged** |
| 8 | Self-sufficient session (keyring, agent, udisks2, gvfs, upower, udiskie, rtkit) | **merged**; RT audio open (section 3) |
| 9 | Power menu, incl. reboot into Windows | **merged**; Suspend left out (section 3b) |
| 10 | Screen capture: window/output/freeze, recording, instant replay | 10a screenshots **merged**; 10b recording/replay + Capture menu tested; armed replay measured at ~+22 W GPU continuously (docs/home.md), so it stays manual. Auto-arming from a GameMode hook was **declined** 2026-11-17 as unnecessary |
| 11 | Launcher search: elephant `files` + `websearch` | **merged** |
| 12 | Firmware updates (fwupd) | **merged**; findings in section 3c |
| 13 | direnv + nix-direnv, repo devShell/formatter | **merged** (no formatter output on purpose: the repo is not uniformly formatted) |
| 14 | Regional formats (dates, A4, metric) | **merged**; verified 2026-11-17 |
| 15 | Printing and scanning | not started |
| 16 | Calendar sync (gnome-calendar has no accounts) | **declined** 2026-10-31: Dani keeps no calendar and does not want a Google token on an unencrypted laptop. Branch `feat/calendar-sync` (67bd4ae) parked: declares gnome-calendar/EDS/GOA instead of inheriting them from cinnamon.nix (closure unchanged) - merge it if Cinnamon is ever dropped. If a calendar is wanted later: gnome-calendar's local "On This Computer" calendar, or a non-Google CalDAV |
| 17 | Phone integration (KDE Connect) | **declined** 2026-10-31, not needed now |

**Considered and excluded** (don't re-propose without new evidence):
hibernate (zero suspends in the journal since 2026-04, machine lives docked);
out-of-memory protection (zero OOM kills since 2026-04); firewall hardening
(only key-only sshd and Tailscale are exposed); Secure Boot (off, but the threat
model is theft — revisit after LUKS); Syncthing (other tailnet machines offline,
notes already sync via git + Obsidian Sync); captive-portal handling (no
evidence of a problem); pausing restic backup/check timers on mobile data
(declined 2026-11-17: WG internet due shortly, five weeks left away).
