# Roadmap, staged work & known issues

What's deliberately not-yet-done, what's half-built and waiting, and the
mistakes already paid for (encoded as runbook steps so they don't recur).

## Staged: LUKS disk encryption + remote unlock

Disk encryption is **deliberately not enabled on the real machines yet**. It
was deferred until NixOS proved itself as a daily driver and backups were in
place — both now true (restore-tested 2026-07-13), so LUKS is the active next
migration.

Everything is built and rehearsed; only the legionix cutover remains:

- `modules/nixos/disko-luks.nix` — LUKS2 + btrfs, identical subvolume layout to
  `disko.nix`. Already **live on `danixos-vm`**.
- `modules/nixos/initrd-ssh.nix` — remote passphrase entry over SSH from the
  initrd. Already **live on `danixos-vm`** (with `virtio_net` in the initrd;
  legionix will use `r8169` for its wired NIC).

**The step-by-step migration and recovery procedure lives in
[luks-runbook.md](luks-runbook.md)** — the copy-paste-ready source of truth:
remote unlock, three recovery drills (forgotten passphrase → recovery key,
damaged header → restore, total loss → reinstall), and the ordered legionix
migration-day sequence. Follow that on cutover day; don't work from a summary.

A disko install wipes and recreates the disk, so the cutover is a **reinstall,
not an in-place conversion** — the restore-tested restic backup is the safety
net, and the passphrase prompt appears at initrd, **before** SDDM. Once LUKS
lands, the clipboard-history TTL note in `clipboard.nix` ("plaintext until the
disk is encrypted") is satisfied.

## Half-built: impermanence

`disko.nix` (and `disko-luks.nix`) already create the subvolumes an
impermanence setup needs — `/root-blank`, `/snapshots`, `/snapshots/root`,
`/snapshots/persist` — and mount `/persist` as `neededForBoot`. **Nothing wires
them up yet**: there's no boot-time rollback of `/` to `/root-blank`, and
`/persist` isn't populated with opt-in state. This is scaffolding for a future
"wipe `/` on every boot, keep only `/persist`" setup. Pairs naturally with the
LUKS work.

## Also on the list

- **Flake / disko dedup** — `disko.nix` and `disko-luks.nix` are ~90% identical
  (same subvolume tree). Worth factoring the layout into one shared expression
  the two thin wrappers reuse.
- **`danix-hp` has no disk device set** — `disko.devices.disk.main.device` is
  unset in `hosts/danix-hp/default.nix`; an install fails until it's filled in
  ([install.md](install.md#1-find-the-disk-id)).
- **IntelliJ Wayland** — the WLToolkit vmoptions fix is applied manually in the
  IDE, not in the repo; key-storm verification was still pending.

## Known issues & install post-mortems

### The 2025 fresh-install failures

Remembered for a while as an "SDDM lock-up", but actually **two disko-era
mistakes**, both now encoded as runbook steps:

1. `hardware-configuration.nix` copied from another machine instead of
   regenerated → missing `boot.initrd.availableKernelModules` for the disk
   controller → initrd can't find the disk → boot dies before the display
   manager. **Fix:** always regenerate on the target
   ([install.md step 2](install.md#2-new-machine-create-the-host)).
2. Volatile `/dev/sda`-style device naming. **Fix:** `/dev/disk/by-id/…`
   ([install.md step 1](install.md#1-find-the-disk-id)).

### Boot corruption incident (2025, legionix)

The ESP was likely damaged while the previous OS (Omarchy) was installed —
plausibly a failed update. Exact repair commands weren't recorded (lesson:
document incidents immediately). What matters going forward: a disko install
recreates the GPT + a fresh ESP, so prior-OS corruption can't carry over; ESP
repair steps are in [operations.md](operations.md#disk-health).

### SDDM greeter on Wayland

The Wayland SDDM greeter stacks all windows on one output (laptop panel goes
black) and kwin is unstable on the closed NVIDIA driver, so the greeter runs on
**X11** (`wayland.enable = false` in `desktop/sddm.nix`). Only the greeter —
the Hyprland session is Wayland. Not a bug to "fix"; a deliberate workaround.
