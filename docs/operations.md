# Operations — day-to-day & testing

Running, maintaining, and safely changing the machines.

## Rebuilding

```bash
# Apply config changes to the running machine
sudo nixos-rebuild switch --flake .#<host>
nh os switch .                 # ergonomic equivalent; picks host from hostname

# Build/evaluate without switching (safe check that it compiles)
nixos-rebuild build --flake .#<host>
nh os build .

# Stage for next boot instead of activating now
sudo nixos-rebuild boot --flake .#<host>

# Roll back if a rebuild misbehaves
sudo nixos-rebuild switch --rollback     # or pick an older entry in the 1s boot menu
```

Updating inputs:

```bash
nix flake update                 # bump every input in flake.lock
nix flake lock --update-input nixpkgs   # bump just one
sudo nixos-rebuild switch --flake .#<host>
```

> One rebuild covers **both** the system and the Home Manager layer — there is
> no separate `home-manager switch` (see [architecture.md](architecture.md#home-manager-as-a-nixos-module)).
> If a rebuild fails on a "would be clobbered" dotfile, HM saved the old one as
> `*.hm-backup`.

## Backups (restic)

Nightly at 20:00 to a restic REST server over Tailscale
(`modules/nixos/restic.nix`). The wrapper is `restic-remote`:

```bash
sudo restic-remote snapshots                 # list snapshots
sudo restic-remote check                      # repo integrity — run monthly
sudo restic-remote stats                      # size / dedup
sudo restic-remote restore latest --target /tmp/restore-test --include <path>
sudo restic-remote unlock                     # clear a stale lock (see below)
```

### Restore test — part of setup, not optional

Restore a directory, diff it against the live copy, expect only post-snapshot
edits to differ:

```bash
sudo restic-remote restore latest --target /tmp/restore-test --include /home/dani/<dir>
diff -r /home/dani/<dir> /tmp/restore-test/home/dani/<dir>
```

Last verified: 2026-07-13 (765 files, 56 MiB, snapshot `3fa1fa19`).

### When a backup fails

- **You'll know:** a critical desktop notification fires, and the waybar
  backup module turns into a blinking red pill. A line is appended to
  `~/BACKUP-FAILED.txt` (waybar right-click acknowledges/truncates it).
- **Investigate:** `journalctl -u restic-backups-remote.service -e`.
  Logs persist across reboots (`diagnostics.nix`).
- **Lock collisions:** the backup runs `backup` → `unlock` (clears *stale*
  locks) → `forget --prune`. A *live* concurrent `restic` run (e.g. you ran one
  by hand near 20:00) holds a real lock; `--retry-lock 30m` (in `restic.nix`)
  now makes both steps wait rather than exit. If ever truly stuck:
  `sudo restic-remote unlock`.

## Secrets (agenix)

Encrypted `.age` files in `secrets/`, recipients in `secrets/secrets.nix`
(user keys edit; host keys decrypt at boot).

```bash
# Edit (uses your ~/.ssh key — must be listed under `users` in secrets.nix)
cd secrets && nix run github:ryantm/agenix -- -e restic-env.age

# Rekey after changing recipients (new host key, new user key)
cd secrets && nix run github:ryantm/agenix -- -r
```

> **Quote values in env-style secrets** (`VAR='value'`) — the restic wrapper
> sources them with a shell; unquoted `&`/`$`/spaces truncate silently.

Adding a host as a recipient is part of [install.md](install.md#3-secrets-agenix).

## Disk health

`smartd` (`hardware-health.nix`) monitors SMART in the background. Manual:

```bash
sudo smartctl -a /dev/disk/by-id/<disk-id>      # SMART status
sudo btrfs scrub start -B /                     # verify checksums (btrfs)
sudo btrfs device stats /                       # accumulated error counters
sudo fsck.vfat -n /dev/disk/by-id/<disk>-part1  # check ESP (read-only)
```

If the ESP misbehaves: check with `fsck.vfat -n`; repair with `-a` (unmount
`/boot` first); if bootloader files are damaged,
`sudo nixos-rebuild boot --install-bootloader`. A disko install recreates the
GPT + a fresh ESP, so corruption from a previous OS can't carry into a
reinstall (see [roadmap.md](roadmap.md) for the 2025 incident).

## Garbage collection & store

Automatic (`base.nix`): weekly `nh clean` (`--keep-since 14d --keep 10`), weekly
`nix.optimise`, `auto-optimise-store`. Manual:

```bash
nh clean all                     # GC per the keep policy
nix store gc                     # raw GC
nix store optimise               # dedup the store
```

Boot entries are capped at 10 (`configurationLimit`).

## Wallpaper, lock, notifications (quick reference)

- **Wallpaper:** `$mod CTRL+W` → waytrogen picker → applies to both monitors.
- **Lock:** `$mod+Escape` (manual only; no idle auto-lock). Locks before
  suspend automatically.
- **Notifications:** persist until dismissed — `$mod+'` newest,
  `$mod SHIFT+'` all, `$mod CTRL+'` restore last.
- **Keybind palette:** `$mod+/` — searchable list of *live* binds.
- **Clipboard:** `$mod+P` history, `$mod SHIFT+P` wipe;
  `bw get password <item> | pwcopy` to copy a secret unrecorded.

## Testing a change

Match the risk to the method:

- **Config that only affects the user session or a service** — rebuild and use
  it. `nixos-rebuild build` first if you want to confirm it evaluates.
- **A GUI/desktop change** — rebuild and exercise the actual flow (launch the
  app, trigger the bind); don't trust evaluation alone for anything visual.
- **Anything touching disks, boot, LUKS, or the initrd** — **rehearse in
  `danixos-vm` first.** The flake keeps the VM wired identically
  (`mkHost`), so behavior transfers. Typical loop:
  1. Make the change apply to the VM (it already imports `disko-luks.nix` +
     `initrd-ssh.nix`).
  2. `nix run github:nix-community/nixos-anywhere -- --flake .#danixos-vm …`
     against the VM (or rebuild in-place for non-partition changes).
  3. Reboot the VM, confirm the passphrase prompt / remote unlock
     (`ssh -p 2222 root@<vm-ip>`), confirm it boots.
  4. Only then port to legionix (swap `disko.nix` → `disko-luks.nix`, add
     `initrd-ssh.nix` + the `r8169` initrd module).

The exact VM commands (SSH aliases, the three recovery drills, the reinstall
invocation) are in [luks-runbook.md](luks-runbook.md); [roadmap.md](roadmap.md)
has the LUKS staging rationale.
