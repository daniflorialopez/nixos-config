# Fresh-install runbook (nixos-anywhere + disko)

Installs a host from scratch onto a target machine, partitioning with disko
and deploying this flake with nixos-anywhere. The target boots any NixOS
installer ISO with SSH enabled (or is already running Linux with root SSH
access).

> **This destroys everything on the target disk.** disko recreates the GPT
> table and all filesystems.

## 0. Prerequisites

- The target is reachable over SSH as `root@<target-ip>` (installer ISO with
  an SSH key added, or an existing Linux with root SSH).
- You have this repo checked out on your working machine with a clean-ish tree.
- For a machine that will run secrets (restic), read [step 3](#3-secrets-agenix)
  first — the ordering matters.

## 1. Find the disk ID

Never use `/dev/sda`-style names in the config — they change between boots and
machines and were a root cause of the failed legionix install in 2025. On the
**target**:

```bash
ls -l /dev/disk/by-id/ | grep -v part
# or match by model/serial:
lsblk -o NAME,MODEL,SERIAL,SIZE
```

Pick the stable ID (prefix `nvme-…` or `ata-…`; avoid the `wwn-`/`-eui`
duplicates for readability) and set it in `hosts/<host>/default.nix`:

```nix
disko.devices.disk.main.device = "/dev/disk/by-id/nvme-SAMSUNG_…";
```

(The VM is the exception: `danixos-vm` uses `/dev/vda`, stable inside libvirt.)

## 2. New machine? Create the host

1. Copy an existing host dir:
   `cp -r hosts/legionix hosts/<newhost>`, then trim host-specific modules you
   don't want (`gpu.nix`, `corne.nix`, `restic.nix`, …) from its
   `default.nix`. See [hosts.md](hosts.md) for what each host imports.
2. Set `networking.hostName` and the disk ID from step 1.
3. Add a `nixosConfigurations.<newhost> = mkHost "<newhost>";` line in
   `flake.nix`.
4. Regenerate `hardware-configuration.nix` **on the target**:

   ```bash
   nixos-generate-config --no-filesystems --show-hardware-config
   ```

   `--no-filesystems` because disko owns the filesystems. Save the output to
   `hosts/<newhost>/hardware-configuration.nix`.

   > **Never copy `hardware-configuration.nix` from another machine.** It
   > encodes that machine's `boot.initrd.availableKernelModules` for its disk
   > controller. With the wrong list the initrd can't find the disk and the
   > boot dies before the display manager — one of the two 2025 legionix
   > install failures (the other was `/dev/sda` naming, fixed in step 1).

## 3. Secrets (agenix)

Secrets are decrypted at boot with the **host's** SSH host key, which does not
exist until after the install. For a new host that needs secrets (e.g.
restic):

1. Install first with secret-using modules commented out, or accept the
   activation warnings on first build.
2. After first boot, grab the host key and add it to the recipient list:
   ```bash
   ssh-keyscan -t ed25519 <host>       # copy the key
   # add it to secrets/secrets.nix (see the `legionix = "ssh-ed25519 …"` line)
   ```
3. Rekey so the host can decrypt, then rebuild:
   ```bash
   cd secrets && nix run github:ryantm/agenix -- -r
   git commit -am "secrets: add <host> as recipient" && sudo nixos-rebuild switch --flake .#<host>
   ```

Editing a secret as your user (no sudo — uses your `~/.ssh` key, which must be
in `secrets.nix`):

```bash
cd secrets && nix run github:ryantm/agenix -- -e restic-env.age
```

> **Quote values in env-style secrets** (`VAR='value'`). The restic wrapper
> sources them with a shell; unquoted `&`/`$`/spaces silently truncate the
> value. This once manifested as 401s from the REST server while *scheduled*
> backups kept working — because systemd passed the file differently.

## 4. Run nixos-anywhere

From this repo, against the booted target:

```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake .#<host> root@<target-ip>
```

For a LUKS host (see [roadmap.md](roadmap.md)), nixos-anywhere also needs the
initial passphrase for the `luksFormat`:

```bash
# disko-luks.nix reads the passphrase from /tmp/disk.key at install time only
echo -n "your-passphrase" > /tmp/disk.key
nix run github:nix-community/nixos-anywhere -- \
  --flake .#<host> --disk-encryption-keys /tmp/disk.key /tmp/disk.key \
  root@<target-ip>
```

This partitions with disko, installs, and reboots.

## 5. First login & post-install

- Root SSH is disabled (`modules/nixos/access.nix`). Log in as `dani` over SSH
  with the authorized key baked into `modules/nixos/users/dani.nix`, then set a
  password with `passwd` (the account is `mutableUsers = true`; on the VM the
  initial password is `changeme`).
- Generate the user SSH key and register it:
  ```bash
  ssh-keygen -t ed25519 -C "dani@<host>"
  gh auth login   # or paste ~/.ssh/id_ed25519.pub into github.com/settings/keys
  ```
  If this key should edit secrets, add it to `users` in `secrets/secrets.nix`
  and rekey (`agenix -r`).
- Join the tailnet: `sudo tailscale up`.
- If the host runs backups, verify: `sudo restic-remote snapshots`, then do a
  restore test (see [operations.md](operations.md#backups-restic)).

## New-host checklist

- [ ] Disk ID set in `hosts/<host>/default.nix` (step 1)
- [ ] `networking.hostName` set
- [ ] `nixosConfigurations.<host>` added to `flake.nix`
- [ ] `hardware-configuration.nix` **regenerated on the target** (step 2)
- [ ] Module import list trimmed to what the machine needs ([hosts.md](hosts.md))
- [ ] Secrets: host key added + rekeyed if the host uses any (step 3)
- [ ] Post-install: password, SSH key, tailscale, backup verify (step 5)
