# Hosts

Each host is a thin entry point: `hosts/<host>/default.nix` sets the hostname
and disk device, then imports the shared modules it wants plus its own
`hardware-configuration.nix`. The differences between hosts are entirely in
*which* modules they import.

## Module matrix

Which `modules/nixos/*` (and host-local files) each host imports. See
[modules.md](modules.md) for what each does.

| Module / file            | legionix | danix-hp | danixos-vm |
| ------------------------ | :------: | :------: | :--------: |
| users/dani               | ✅ | ✅ | ✅ |
| access                   | ✅ | ✅ | ✅ |
| base                     | ✅ | ✅ | ✅ |
| virtualisation           | ✅ | ✅ | ✅ |
| security                 | ✅ | ✅ | ✅ |
| gaming                   | ✅ | ✅ | ✅ |
| tailscale                | ✅ | — | — |
| restic                   | ✅ | — | — |
| bluetooth                | ✅ | ✅ | — |
| disko (plain btrfs)      | ✅ | ✅ | — |
| **disko-luks**           | — | — | ✅ |
| **initrd-ssh**           | — | — | ✅ |
| tlp                      | ✅ | ✅ | — |
| fonts                    | ✅ | ✅ | — |
| keyd                     | ✅ | ✅ | — |
| corne                    | ✅ | — | — |
| hardware-health (smartd) | ✅ | ✅ | — |
| diagnostics              | ✅ | ✅ | — |
| gpu (NVIDIA)             | ✅ | — | — |
| desktop/sddm             | ✅ | ✅ | — |
| desktop/hyprland         | ✅ | ✅ | — (commented) |
| desktop/cinnamon         | ✅ | ✅ | ✅ |

The VM deliberately runs a **minimal, Cinnamon-only** graphical stack: it
exists to rehearse disk/boot changes, not to be a daily desktop, so it skips
the whole Hyprland layer, backups, and laptop hardware modules.

## legionix — main laptop

Lenovo Legion, NVIDIA GPU. The reference machine everything else is trimmed
down from.

- **Disk:** `nvme-SAMSUNG_MZVL21T0HCLR-…` (set in `default.nix`), plain btrfs
  via `disko.nix` (no LUKS yet — that's the pending migration).
- **GPU** (`gpu.nix`): proprietary NVIDIA driver (`open = false`),
  modesetting on, power management on. `NVreg_EnableGpuFirmware=0` via
  modprobe — a stability workaround for the closed driver. The waybar GPU
  temp module (`home/dani/wm/waybar.nix`) reads `nvidia-smi` here; it
  self-hides on the other hosts.
- **Desktop** (`desktop.nix`): SDDM greeter, Hyprland (default session,
  `hyprland-uwsm`), Cinnamon as a selectable fallback.
- **Extras:** tailscale + restic (nightly backups depend on the tailnet),
  Corne split-keyboard tooling (`corne.nix`), TLP power management.
- **Migration target:** on LUKS day this host swaps `disko.nix` →
  `disko-luks.nix` and adds `initrd-ssh.nix` (plus the `r8169` wired-NIC
  kernel module in the initrd). See [roadmap.md](roadmap.md).

## danix-hp — secondary laptop

HP laptop. Same desktop as legionix, minus the Legion-specific hardware.

- ⚠ **`disko.devices.disk.main.device` is not set.** `default.nix` has no disk
  ID, so an install will fail until you add one (see
  [install.md](install.md#1-find-the-disk-id)).
- No NVIDIA (`gpu.nix` not imported), no tailscale, no restic, no Corne.
- Otherwise mirrors legionix: SDDM + Hyprland + Cinnamon, keyd, TLP, fonts,
  bluetooth, smartd.

## danixos-vm — test bed

libvirt VM. The rehearsal ground for anything risky at the disk/boot level, so
the flake keeps it wired identically to the real hosts (same `mkHost`).

- **Disk:** `/dev/vda` (virtio, stable across VM rebuilds).
- **Encryption:** imports `disko-luks.nix` (LUKS2 + btrfs) instead of the plain
  `disko.nix` — this is where the legionix LUKS layout is proven before it
  touches real data.
- **Remote unlock:** imports `initrd-ssh.nix` — a tiny sshd in the initrd so
  you can type the LUKS passphrase over SSH. `boot.initrd.availableKernelModules
  = [ "virtio_net" ]` puts the virtio NIC in the initrd so that sshd has a
  network (legionix will use `r8169` instead).
- **Desktop:** Cinnamon only; the Hyprland import is left commented.
- **Convenience:** `users.users.dani.initialPassword = "changeme"` so a fresh
  install (the disk gets wiped repeatedly here) comes up with a usable console
  login. With `mutableUsers` this only applies at first user creation, so it
  never affects the real hosts.

See [operations.md](operations.md#testing-a-change) for the VM rehearsal loop.
