# LUKS runbook — recovery drills & legionix migration

Everything here is copy-paste ready. Local commands are **fish** (legionix);
commands after an `ssh ... '...'` run as bash on the target.

The rehearsal target is `danixos-vm` (LUKS2 + btrfs via `disko-luks.nix`,
remote unlock via `initrd-ssh.nix`). Its secrets are throwaway by design:

| What | Value / location |
|---|---|
| VM LUKS passphrase | `rehearsal` (file: `~/.local/share/danixos-vm-rehearsal/disk.key`) |
| VM recovery key | Bitwarden → `danixos-vm LUKS recovery` (slot 1) |
| VM initrd host key | `~/.local/share/danixos-vm-rehearsal/extra/etc/secrets/initrd/` |
| VM console password | user `dani`, password `changeme` |
| Scoped known_hosts | `~/.local/share/danixos-vm-rehearsal/known_hosts` |
| LUKS partition (VM) | `/dev/vda2` → mapper name `crypted` |

**legionix secrets are NOT throwaway.** On migration day generate fresh ones
and never write them to this repo.

Handy snippets used throughout:

```fish
# VM's IP (usually stays 192.168.122.167 — same MAC, same lease)
set ip (virsh --connect qemu:///system domifaddr danixos-vm | awk '/ipv4/ {split($4,a,"/"); print a[1]}')

# SSH aliases for the two faces of the VM
alias vmboot "ssh -p 2222 -o UserKnownHostsFile=$HOME/.local/share/danixos-vm-rehearsal/known_hosts root@$ip"   # initrd (unlock)
alias vmsys  "ssh -o UserKnownHostsFile=$HOME/.local/share/danixos-vm-rehearsal/known_hosts dani@$ip"           # booted system
```

---

## Remote unlock (the everyday move)

After any reboot the machine waits at the LUKS prompt. From anywhere with
your key:

```fish
virsh --connect qemu:///system start danixos-vm   # (VM only) power it on
vmboot                                            # lands in the passphrase prompt
# type passphrase (or recovery key) → connection drops → machine boots
```

The console prompt keeps working in parallel — remote unlock is an extra
door, not a replacement.

---

## Drill 1 — passphrase forgotten → recovery key

*Proves: forgetting the passphrase is not a brick.*

Setup (already done on the VM, 2026-07-24; repeat on legionix on migration
day): a second key slot holding a long random recovery key.

```fish
# generate a recovery key → store in Bitwarden BEFORE the next step
tr -dc 'a-z0-9' < /dev/urandom | head -c 32 | sed 's/.\{4\}/&-/g;s/-$//' > /tmp/rk; cat /tmp/rk; echo

# push new key + existing passphrase, add slot, verify, clean up — ALL in
# one ssh session: /dev/shm files from one session are not guaranteed to
# survive into the next (bit us twice in rehearsals). Recovery key comes
# in via stdin; the throwaway VM passphrase is embedded inline.
vmsys 'cat > /dev/shm/nk; printf "%s" rehearsal > /dev/shm/ok; echo changeme | sudo -S -p "" cryptsetup luksAddKey /dev/vda2 /dev/shm/nk --key-file /dev/shm/ok; and echo SLOT-ADDED; echo changeme | sudo -S -p "" cryptsetup open --test-passphrase --key-file /dev/shm/nk /dev/vda2; and echo RECOVERY-KEY-UNLOCKS; rm -f /dev/shm/ok /dev/shm/nk' < /tmp/rk
rm /tmp/rk
```

(On legionix this is done at the machine's own keyboard — no ssh push,
no /dev/shm dance.)

The drill itself — do this by hand, that's the point:

```fish
vmsys 'sudo systemctl reboot' ; sleep 20 ; vmboot
# at "Passphrase for ...": type the RECOVERY KEY from Bitwarden, not the passphrase
vmsys hostname   # boots → drill passed
```

---

## Drill 2 — damaged LUKS header → restore from backup

*Proves: a corrupted header is not a brick, and the initrd SSH shell is a
rescue environment.*

Step 1 — take the header backup (this artifact is the whole drill; on
legionix, keep it next to the restic repo, NOT on the encrypted disk):

```fish
vmsys 'echo changeme | sudo -S -p "" cryptsetup luksHeaderBackup /dev/vda2 --header-backup-file /tmp/luks-header.img; sudo chown dani /tmp/luks-header.img'
scp -o UserKnownHostsFile=$HOME/.local/share/danixos-vm-rehearsal/known_hosts dani@$ip:/tmp/luks-header.img ~/.local/share/danixos-vm-rehearsal/
```

Step 2 — break it (zeroes both LUKS2 metadata copies and the start of the
keyslot area):

```fish
vmsys 'echo changeme | sudo -S -p "" dd if=/dev/zero of=/dev/vda2 bs=1M count=1 conv=notrunc; sudo systemctl reboot --force'
sleep 20; vmboot
# systemd stage 1: there is NO passphrase prompt — systemd-cryptsetup fails
# at once ("Failed to load LUKS superblock") and you land straight in the
# initrd shell. The initrd also drops into emergency mode; sshd survives it
# (verified 2026-10-24), so nothing is counting down. DON'T close the connection.
```

Step 3 — restore from the initrd shell (a second terminal pushes the backup
in over the same port; the initrd has no scp, `cat` over ssh works):

```fish
vmboot 'cat > /luks-header.img' < ~/.local/share/danixos-vm-rehearsal/luks-header.img
```

back in the initrd shell (first terminal):

```sh
cryptsetup luksHeaderRestore /dev/vda2 --header-backup-file /luks-header.img
# confirm YES. (If cryptsetup is ever missing from the initrd, the backup is a
# raw copy of the first 16 MiB and the data starts right after it, so
#   dd if=/luks-header.img of=/dev/vda2 bs=1M conv=notrunc,fsync
# is equivalent — that is how the 2026-10-24 drill was recovered.)

# the failed unlock has to be retried, then emergency mode left:
systemctl restart --no-block systemd-cryptsetup@crypted.service
systemd-tty-ask-password-agent    # type the normal passphrase
systemctl default                 # leave emergency mode → boot continues
# the session then hangs (the initrd drops its address first): Enter, ~ .
```

Fallback if the initrd shell ever feels too tight: the NixOS ISO is still
attached (`virt-xml ... --edit --boot cdrom,hd`, restore with the same two
commands, flip boot back).

---

## Drill 3 — total loss → reinstall from nothing

*Proves: even "lost the passphrase AND the recovery key AND the header
backup" costs ~10 minutes plus a restic restore, not the machine.*

This is exactly the flow already rehearsed end-to-end on 2026-07-24:

```fish
# 1. boot the VM from the installer ISO
virsh --connect qemu:///system destroy danixos-vm
virt-xml --connect qemu:///system danixos-vm --edit --boot cdrom,hd
virsh --connect qemu:///system start danixos-vm
# in the virt-manager console once logged in:  sudo passwd nixos   (pick e.g. "rehearsal")

# 2. reinstall (wipes the disk, places the initrd host key, sets the LUKS key)
set ip (virsh --connect qemu:///system domifaddr danixos-vm | awk '/ipv4/ {split($4,a,"/"); print a[1]}')
SSHPASS=rehearsal nix run github:nix-community/nixos-anywhere -- \
  --flake ~/nixos-config#danixos-vm \
  --target-host nixos@$ip \
  --env-password \
  --extra-files ~/.local/share/danixos-vm-rehearsal/extra \
  --disk-encryption-keys /tmp/disk.key ~/.local/share/danixos-vm-rehearsal/disk.key \
  --phases kexec,disko,install

# 3. boot from disk again
virsh --connect qemu:///system shutdown danixos-vm; sleep 10
virt-xml --connect qemu:///system danixos-vm --edit --boot hd,cdrom
virsh --connect qemu:///system start danixos-vm
# the reinstall regenerated the SYSTEM host key (port 22) but the initrd one
# was re-placed via --extra-files, so drop only the stale port-22 entry:
ssh-keygen -R $ip -f ~/.local/share/danixos-vm-rehearsal/known_hosts
# unlock (vmboot), then redo Drill 1 setup (new recovery key) + Drill 2 step 1 (new header backup)

# 4. user data: restic restore, same as any host (see modules/nixos/restic.nix)
```

---

## Drill 4 — reinstall with Windows on the same disk

*Proves: the reinstall replaces only the Linux partition. Windows' partitions,
its boot manager on the shared ESP, and every partition GUID come through
byte-identical — even with nixos-anywhere's default (destroy) mode.*

Why it works: `disko.devices.disk.main.destroy = false` empties disko's wipe
list, and the p1/p2 GUIDs are pinned so the GPT step re-applies the same
values (see `hosts/legionix/default.nix`). disko never touches partitions it is
not told about. Passed 2026-10-25.

The helpers live outside the repo, in `~/.local/share/danixos-vm-rehearsal/`:
`drill4-prep.sh` (lays the VM disk out like legionix: ESP + fake Windows Boot
Manager, plain-btrfs Linux, then MSR/NTFS/recovery stand-ins filled with random
bytes) and `drill4-fingerprint.sh` (partition table + checksums of everything
that must survive).

```fish
# 1. boot the installer ISO, then in the VM window: sudo passwd nixos  (rehearsal)
virsh --connect qemu:///system destroy danixos-vm
virt-xml --connect qemu:///system danixos-vm --edit --boot cdrom,hd
virsh --connect qemu:///system start danixos-vm
set ip (virsh --connect qemu:///system domifaddr danixos-vm --source arp | awk '/ipv4/ {split($4,a,"/"); print a[1]}')

# 2. legionix-like layout + the "before" fingerprint (the ISO's host key is new
#    every boot, hence no known_hosts)
set r ~/.local/share/danixos-vm-rehearsal
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no nixos@$ip sudo bash -s < $r/drill4-prep.sh
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no nixos@$ip sudo bash -s < $r/drill4-fingerprint.sh > $r/drill4-before.txt

# 3. clear stale signatures from the LINUX partition only (see below), then the
#    exact Drill 3 install command
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no nixos@$ip 'sudo wipefs -a /dev/disk/by-partlabel/disk-main-danixos-vm'
# → Drill 3 step 2 (env SSHPASS=rehearsal nix run … --phases kexec,disko,install)
#   expected: "Could not create partition 1/2" then "completed successfully"
#   (existing partitions kept), no mkfs.vfat, a luksFormat of p2 only

# 4. boot from disk, unlock (vmboot), then the "after" fingerprint and the diff
virsh --connect qemu:///system shutdown danixos-vm
virt-xml --connect qemu:///system danixos-vm --edit --boot hd,cdrom
virsh --connect qemu:///system start danixos-vm
ssh-keygen -R $ip -f $r/known_hosts
begin; echo changeme; cat $r/drill4-fingerprint.sh; end | ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$r/known_hosts dani@$ip 'sudo -S -p "" bash -s' > $r/drill4-after.txt
diff $r/drill4-before.txt $r/drill4-after.txt   # must print nothing
```

**The stale-header trap (found in this drill):** `mkfs.btrfs` does not
overwrite the first 64 KiB of a partition, where an old LUKS header lives. The
VM's partition started where July's encrypted one did, so disko's "is it
already LUKS?" check said yes, skipped `luksFormat`, and the open failed with
"No key available with this passphrase". `wipefs -a` on the Linux partition
removes it. legionix may carry the same leftover from the Omarchy install,
which encrypted by default — check with `sudo wipefs /dev/nvme0n1p2` (lists,
erases nothing).

After the drill the VM's LUKS container is new: the Bitwarden recovery key and
`luks-header.img` belong to the old one. Redo Drill 1 setup and Drill 2 step 1
before the next rehearsal.

---

## Migration day — legionix

Only after all four drills are done and you're convinced. Order matters.
**Windows stays**: nothing below may touch p1's filesystem, p3–p5, or any
partition GUID (Drill 4).

1. **Fresh backup, verified first**: run the restic backup, then
   `restic check --read-data-subset=5%` and a spot-restore of one recent file.
   The install wipes the Linux partition — the backup IS NixOS until step 6.
   Also copy an image of the ESP (`/dev/nvme0n1p1`, 1 GiB) off the disk, and
   note that Steam (319 GB) is excluded from restic.
2. **Config**: `hosts/legionix/...` imports `disko-luks.nix` (instead of
   `disko.nix`) + `initrd-ssh.nix`; add `"r8169"` to
   `boot.initrd.availableKernelModules` (wired NIC — WiFi unlock is out of
   scope by design). Keep the `destroy = false` + pinned-GUID block in
   `hosts/legionix/default.nix` exactly as it is. Still open before this step
   (gap study 1d/1e): a declarative password (the fresh `dani` is otherwise
   locked) and carrying `/etc/ssh/ssh_host_*` + `/var/lib/tailscale` into the
   `--extra-files` tree.
3. **Secrets** (fresh, per-host, not in repo):
   ```fish
   mkdir -p /tmp/legionix-extra/etc/secrets/initrd
   ssh-keygen -t ed25519 -N "" -f /tmp/legionix-extra/etc/secrets/initrd/ssh_host_ed25519_key
   # strong passphrase → Bitwarden first, then:
   printf '%s' 'THE-REAL-PASSPHRASE' > /tmp/legionix.key
   ```
4. **Install** from another machine (danarchy) with the legionix target
   booted from the installer USB — Drill 4's sequence, swapping flake attr,
   target IP, extra-files dir, and key file: fingerprint first (adapt
   `drill4-fingerprint.sh` to `/dev/nvme0n1`), `wipefs -a` on
   `/dev/disk/by-partlabel/disk-main-legionix` ONLY, the install, then the
   fingerprint diff — and boot Windows once from the menu before moving on.
5. **Immediately after first unlock**: Drill 1 setup (recovery key → second
   slot → Bitwarden) and Drill 2 step 1 (header backup → store off-disk,
   e.g. next to the restic repo). Do not postpone these.
6. **Restore** user data with restic; re-pair Bluetooth, re-login sessions.
7. **Test the remote unlock once** from danarchy while the machine is
   physically reachable: `ssh -p 2222 root@legionix-ip`. If it times out,
   check link/DHCP first: the initrd gets its address from the systemd-networkd
   unit `10-initrd-wired` in `modules/nixos/initrd-ssh.nix` (matches `en*`;
   r8169 must be in the initrd). Nothing waits for that lease, so a missing
   cable never delays the console prompt.
