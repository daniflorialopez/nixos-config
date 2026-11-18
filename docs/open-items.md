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

## 5d. Reverie rice — experimental, branch `rice/reverie`, NOT merged

Second "craziest rice" experiment (2026-11-18). Unrelated to `rice/overdrive`
(which has its own entry on its own branch). One module,
`home/dani/wm/reverie.nix`, and a small Python daemon in
`home/dani/wm/reverie/` (GTK4 + gtk4-layer-shell + cairo) that draws surfaces
the compositor cannot. The module header lists every command.

**What is in it now**, all off or invisible until asked for: the **HUD**
(clock, day arc carrying today's focus history, gauges, every waybar module as
a chip, a to-scale map of every workspace that is also a switcher) on a
blurred capture of the desktop; **zen** (stops waybar; title cards and the HUD
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
  being visually stunning"), the spotlight (styling liked; motion on its
  third version, unjudged). Not yet commented on: zen, ripples, sound, fade.

**Parked from `rice/overdrive`** (Dani, 2026-11-18: store, implement later
once more ideas have been collected — not now):
1. *Noir focus mode* — the whole screen monochrome except the warm attention
   band, as a toggle.
2. *Glow ring* — the screen edge as an ambient channel: position = source,
   colour = severity, steady glow for states, one swell for events.
3. *Liquid glass on windows* — per-window edge refraction via the `hyprglass`
   plugin; needs a build against the exact Hyprland version, so check offline
   feasibility or wait until home. (Reverie's HUD had cairo lenses imitating
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
