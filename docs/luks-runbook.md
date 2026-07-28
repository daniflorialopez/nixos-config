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
# type the passphrase → "No key available with this passphrase" / not a LUKS device.
# You are now locked out. Feel it. Then: Ctrl-C to drop from askpass into the initrd shell — DON'T close the connection.
```

Step 3 — restore from the initrd shell (a second terminal pushes the backup
in over the same port; the initrd has no scp, `cat` over ssh works):

```fish
vmboot 'cat > /luks-header.img' < ~/.local/share/danixos-vm-rehearsal/luks-header.img
```

back in the initrd shell (first terminal):

```sh
cryptsetup luksHeaderRestore /dev/vda2 --header-backup-file /luks-header.img
# confirm YES, then:
cryptsetup-askpass    # type the normal passphrase → boot continues
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

## Migration day — legionix

Only after all three drills are done and you're convinced. Order matters.

1. **Fresh backup, verified first**: run the restic backup, then
   `restic check --read-data-subset=5%` and a spot-restore of one recent file.
   The disko install wipes the disk — the backup IS the machine until step 6.
2. **Config**: `hosts/legionix/...` imports `disko-luks.nix` +
   `initrd-ssh.nix`; add `"r8169"` to `boot.initrd.availableKernelModules`
   (wired NIC — WiFi unlock is out of scope by design); set
   `disko.devices.disk.main.device` to the NVMe by-id path.
3. **Secrets** (fresh, per-host, not in repo):
   ```fish
   mkdir -p /tmp/legionix-extra/etc/secrets/initrd
   ssh-keygen -t ed25519 -N "" -f /tmp/legionix-extra/etc/secrets/initrd/ssh_host_ed25519_key
   # strong passphrase → Bitwarden first, then:
   printf '%s' 'THE-REAL-PASSPHRASE' > /tmp/legionix.key
   ```
4. **Install** from another machine (danarchy) with the legionix target
   booted from the installer USB — same nixos-anywhere invocation as Drill 3,
   swapping flake attr, target IP, extra-files dir, and key file.
5. **Immediately after first unlock**: Drill 1 setup (recovery key → second
   slot → Bitwarden) and Drill 2 step 1 (header backup → store off-disk,
   e.g. next to the restic repo). Do not postpone these.
6. **Restore** user data with restic; re-pair Bluetooth, re-login sessions.
7. **Test the remote unlock once** from danarchy while the machine is
   physically reachable: `ssh -p 2222 root@legionix-ip`. If it times out,
   check link/DHCP timing — first knob is loosening `udhcpc.extraArgs`
   in `modules/nixos/initrd-ssh.nix` (already loosened to `-t 4 -T 2`
   after the VM rehearsal lost the lease race at `-t 2 -T 1`).
