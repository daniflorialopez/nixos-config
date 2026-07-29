# Black-screen / broken-boot rescue (legionix)

You switched or rebooted and the display is dead — usually the proprietary
NVIDIA module failed to load against a new kernel. **Nothing is broken and no
data is at risk.** This is recoverable without a live USB in almost every
case. On the box (or over SSH), run `rescue` to reprint this.

This assumes the disk already unlocked (you got the LUKS passphrase prompt).
If you never reached that prompt, it's a different problem — see
`docs/luks-runbook.md`.

There is deliberately **no custom "safe graphics" boot entry.** On this
laptop the panel is wired to the NVIDIA GPU (BIOS discrete-only, no iGPU),
and the open nouveau driver is too fragile here to trust — every variant
tried either left the panel frozen or crashed the session. The reliable
rescue is the one below, which needs no custom config and cannot break.

---

## Path 1 — Boot a previous generation  (the reliable rescue)

This is the answer to a bad switch, and it always works.

1. Power on and **tap `Space` repeatedly** right after the Lenovo logo to
   hold the boot menu (the timeout is short).
2. The menu lists your recent generations, newest first (last 10 kept).
   Choose the one **from before the switch that broke things** — it's a
   complete, known-good system with a working NVIDIA driver.
3. You're back to a normal desktop immediately.

That older generation stays bootable regardless of what the new one did,
because each generation pins its own kernel *and* driver — a kernel bump
that breaks today's nvidia can't touch yesterday's. Once you're back in,
make it permanent (see "Repair", below) or just carry on.

## Path 2 — Fix it over SSH  (if the screen stays dead)

Every failed boot in testing still came up with networking and sshd — the
display dies, the machine doesn't. So from your phone or another machine **on
your Tailscale network**:

    ssh dani@legionix

Then run the repair commands below. This works even when nothing is on
screen at all.

## Path 3 — Live USB  (the floor: kernel/initrd/LUKS/ESP broken)

If the machine won't boot far enough for Path 1 or 2 — a kernel panic, a
broken initrd, a failed LUKS unlock, or a trashed ESP — boot a **NixOS live
USB**, then:

- unlock and mount the LUKS root, `nixos-enter`, and rebuild/rollback; or
- if the disk itself is gone, restore from restic (see `docs/luks-runbook.md`
  and the restic setup — your backups are the last layer).

---

## Repair (from any console — Path 1's desktop terminal or Path 2's SSH)

**See what broke:**

    journalctl -b -p err --no-pager | tail -50
    dmesg | grep -i nvidia
    systemctl --failed

**Roll back one generation (make the good state the default):**

    sudo nixos-rebuild switch --rollback

(If activating live misbehaves, use `sudo nixos-rebuild boot --rollback`,
then `reboot`.)

**Or fix the config and rebuild:**

    cd ~/nixos-config
    # edit the offending file
    sudo nixos-rebuild boot --flake .#legionix
    reboot

Use `boot`, not `switch`, from a rescue session: it stages the new system
for next boot instead of restarting the graphics stack in place.

**List generations:**

    nixos-rebuild list-generations
    # or:
    sudo nix-env --list-generations -p /nix/var/nix/profiles/system

---

## Habits that keep this easy

- Testing something risky? `sudo nixos-rebuild boot ...` then reboot, so the
  current known-good generation stays the default until you've confirmed the
  new one — and Path 1 is always one menu pick away.
- Don't bother with `nomodeset` or hunting for a text console on this
  machine: the panel only lights under a real graphical modeset, so a bare
  console stays blank whatever you do. If the screen's dead, use SSH (Path 2).
