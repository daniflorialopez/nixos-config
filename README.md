# Dani's NixOS + Home Manager config

Flake-based NixOS configuration for all my machines, with Home Manager,
disko-managed partitioning, agenix secrets and restic backups.

## Hosts

| Host        | Machine                  | Notes                                        |
| ----------- | ------------------------ | -------------------------------------------- |
| `legionix`  | Lenovo Legion laptop     | Main machine. NVIDIA GPU, Hyprland, backups. |
| `danix-hp`  | HP laptop                | ⚠ `disko.devices.disk.main.device` not set — must be filled in before installing (see below). |
| `danixos-vm`| VM for testing           |                                              |

Repo layout:

```
flake.nix            inputs + one nixosConfiguration per host
hosts/<host>/        host entry point, hardware-configuration.nix, host-specific modules
modules/nixos/       shared system modules (disko, restic, tailscale, keyd, ...)
home/dani/           Home Manager config (programs, shell, Hyprland, waybar, ...)
secrets/             agenix-encrypted secrets + secrets.nix recipient list
```

## Fresh install runbook (nixos-anywhere + disko)

Target machine boots any NixOS installer ISO with SSH enabled (or is already
running Linux with root SSH access).

### 1. Find the disk ID

Never use `/dev/sda`-style names in the config — they change between boots
and machines. On the target machine:

```bash
ls -l /dev/disk/by-id/ | grep -v part
# or, to match by model/serial:
lsblk -o NAME,MODEL,SERIAL,SIZE
```

Pick the stable ID of the target disk (prefix `nvme-...` or `ata-...`,
avoid the `wwn-` and `-eui` duplicates for readability). Set it in
`hosts/<host>/default.nix`:

```nix
disko.devices.disk.main.device = "/dev/disk/by-id/nvme-SAMSUNG_...";
```

### 2. New machine? Create the host

1. Copy an existing host dir: `cp -r hosts/legionix hosts/<newhost>`; trim
   host-specific modules (`gpu.nix`, `corne.nix`, `restic.nix`, ...).
2. Set `networking.hostName` and the disk ID from step 1.
3. Add a `nixosConfigurations.<newhost>` entry in `flake.nix` (copy an
   existing block).
4. Regenerate `hardware-configuration.nix` on the target:
   `nixos-generate-config --no-filesystems --show-hardware-config`
   (filesystems come from disko, so `--no-filesystems`).

   **Never copy this file from another machine.** It encodes the detected
   `boot.initrd.availableKernelModules` for *that* machine's disk
   controller; with the wrong list the initrd can't find the disk and the
   boot dies before the display manager. This (plus `/dev/sda`-style
   naming) was the root cause of the failed legionix install in 2025.

### 3. Secrets (agenix)

Secrets are decrypted at boot with the **host's** SSH host key, which does
not exist until after the install. For a new host that needs secrets
(e.g. restic):

1. Install first with secret-using modules commented out, or accept the
   activation warnings.
2. After first boot: `ssh-keyscan -t ed25519 <host>` and add the key to
   `secrets/secrets.nix`.
3. Rekey: `cd secrets && agenix -r` (or
   `nix run github:ryantm/agenix -- -r`), commit, rebuild.

Editing a secret (as user, no sudo — uses your `~/.ssh` key, which must be
listed in `secrets.nix`):

```bash
cd secrets && agenix -e restic-env.age
```

**Quote values in env-style secrets** (`VAR='value'`): the restic wrapper
sources them with a shell, and unquoted `&`/`$`/spaces silently truncate
values (manifested as 401s from the REST server while scheduled backups
kept working).

### 4. Run nixos-anywhere

From this repo, against the booted installer:

```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake .#<host> root@<target-ip>
```

This partitions the disk with disko (**destroys everything on it**),
installs the system and reboots.

### 5. First login & post-install

- Root SSH login is disabled (`access.nix`); log in as `dani` over SSH with
  the authorized key baked into `users/dani.nix`, then run `passwd`.
- Generate the user SSH key and add it to GitHub:

  ```bash
  ssh-keygen -t ed25519 -C "dani@<host>"
  gh auth login   # or paste ~/.ssh/id_ed25519.pub at github.com/settings/keys
  ```

  If this key should be able to edit secrets, add it to `users` in
  `secrets/secrets.nix` and rekey (`agenix -r`).
- `sudo tailscale up` to join the tailnet.
- If the host runs backups, verify: `sudo restic-remote snapshots`.

## Backups (restic → REST server over Tailscale)

- Nightly at 20:00 (`modules/nixos/restic.nix`), `/home/dani` with cache/
  build-artifact excludes, to `rest:https://restic.arm53.xyz/...`.
- On failure: critical desktop notification + a line appended to
  `~/BACKUP-FAILED.txt`.
- Ad-hoc commands via the generated wrapper:

  ```bash
  sudo restic-remote snapshots
  sudo restic-remote check                     # repo integrity (run monthly)
  sudo restic-remote restore latest --target /tmp/restore-test --include <path>
  ```

- **Restore test is part of the setup**, not optional: restore a directory,
  diff it against the live copy, expect only post-snapshot edits to differ.
  Last verified: 2026-07-13 (765 files, 56 MiB, snapshot `3fa1fa19`).

## Disk health

`smartd` (modules/nixos/hardware-health.nix) monitors SMART in the
background. Manual checks:

```bash
sudo smartctl -a /dev/disk/by-id/<disk-id>     # SMART status
sudo btrfs scrub start -B /                    # verify checksums (btrfs)
sudo btrfs device stats /                      # accumulated error counters
sudo fsck.vfat -n /dev/disk/by-id/<disk>-part1 # check ESP (read-only; unmount /boot first for -a repair)
```

### Boot corruption incident (2025, legionix)

The ESP was likely damaged while Omarchy (the previous OS) was installed —
plausibly by a failed update. Exact repair commands were not recorded
(lesson learned: document incidents immediately). What matters going
forward:

- A disko install **recreates the GPT partition table and a fresh ESP**,
  so corruption from a previous OS cannot carry over into a reinstall.
- If the ESP misbehaves on a running system: check with
  `sudo fsck.vfat -n <esp-partition>`; repair with `-a` (unmount `/boot`
  first); if bootloader files are damaged, reinstall them with
  `sudo nixos-rebuild boot --install-bootloader`.

## Monitors

Hyprland monitor + workspace layout lives in `home/dani/wm/hyprland.nix`:
workspaces 1, 4, 5+ on the external `HDMI-A-1`, 2–3 on the laptop panel
`eDP-1`. On a machine with different outputs, adjust the `monitor = [...]`
list and the per-workspace `monitor:` bindings.

## Known issues & install post-mortem

- **The 2025 fresh-install failures** (remembered for a while as an
  "SDDM lock-up") were in fact two disko-era mistakes, both now encoded
  as runbook steps above:
  1. `hardware-configuration.nix` copied from elsewhere instead of
     regenerated → missing initrd kernel modules for the disk controller.
  2. Volatile `/dev/sda` device naming → fixed by `/dev/disk/by-id/...`.
- **Disk encryption (LUKS) is deliberately not enabled.** It was deferred
  until NixOS proved itself as a daily driver and backups were in place.
  Both are now true (restore-tested 2026-07-13), so LUKS is a candidate
  again — test the disko LUKS layout in the `danixos-vm` host first, and
  expect the passphrase prompt at initrd, before SDDM.
- `danix-hp` has no disko disk device set (see hosts table) — set it before
  attempting an install on that machine.
