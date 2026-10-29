# Open items — everything deliberately left out or unfinished

The one place that lists what is **not** done: paused work, parked branches,
known gaps, and the investigation notes needed to pick each one up again.
Last updated 2026-10-29. If you finish something here, delete it here in the
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
- **Windows clock — your step, in Windows.** Windows keeps local time in the
  hardware clock, so NixOS boots 2 hours ahead after a Windows session (4 of 9
  boots checked; once NTP took 20 minutes). In an administrator Command Prompt:
  `reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f`
  then sync the clock once. Verify on the next NixOS boot after Windows
  (`journalctl -k -b | grep "setting system clock"` should match real UTC).

## 3. PipeWire real-time scheduling (follow-up from gap item 8)

`security.rtkit.enable` is on but **does not yet give PipeWire real-time
priority**; `data-loop.0` stays `SCHED_OTHER`. No regression: same as before.

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

- **No Suspend card, deliberately.** Nothing has suspended legionix since at
  least 2026-04 and suspend was never tested on 26.05; on an NVIDIA laptop with
  no usable text console a failed resume means a hard power-off. Test once by
  hand (`systemctl suspend`, then wake it) and, if it comes back with a working
  display, add the card in `home/dani/wm/hyprland.nix`.

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
| 10 | Screen capture: window/output/freeze, recording, instant replay | not started |
| 11 | Launcher search: elephant `files` + `websearch` | **merged** |
| 12 | Firmware updates (fwupd) | **merged**; findings in section 3c |
| 13 | direnv + nix-direnv, repo devShell/formatter | not started |
| 14 | Regional formats (dates, A4, metric) | **merged**; applies from the next login (check `date`, waybar calendar Monday-first) |
| 15 | Printing and scanning | not started |
| 16 | Calendar sync (gnome-calendar has no accounts) | not started |
| 17 | Phone integration (KDE Connect) | not started, optional |

**Considered and excluded** (don't re-propose without new evidence):
hibernate (zero suspends in the journal since 2026-04, machine lives docked);
out-of-memory protection (zero OOM kills since 2026-04); firewall hardening
(only key-only sshd and Tailscale are exposed); Secure Boot (off, but the threat
model is theft — revisit after LUKS); Syncthing (other tailnet machines offline,
notes already sync via git + Obsidian Sync); captive-portal handling (no
evidence of a problem).
