# Black-screen rescue (legionix)

You booted and there's no display — usually the proprietary NVIDIA module
failed to load against a new kernel after a `nixos-rebuild switch`. This is
recoverable **without a live USB**. On the box, run `rescue` to reprint this.

Everything below assumes the disk already unlocked (you got the LUKS
passphrase prompt). If you never even reached the passphrase prompt, this is
a different problem — see `docs/luks-runbook.md`.

---

## 0. Reach the boot menu

Power on and **tap `Space` repeatedly** right after the Lenovo logo — the
systemd-boot timeout is 1 second, so you have to be quick. The menu lists:

- the current generation (the default that just black-screened),
- the same generation tagged **`safe-graphics`** (NVIDIA disabled),
- older generations, newest first (up to 10 kept).

Pick a path below.

---

## Path 1 — Boot the previous generation (fastest, always works)

In the menu, choose the entry **one below the top** (the generation from
before today's switch). It boots your last known-good system with a normal
desktop. You're back online immediately.

This is temporary: the *next* normal boot still defaults to the broken
generation until you fix or roll back (see "Make it stick", below).

## Path 2 — Boot `safe-graphics` (repair from the current generation)

Choose the **`safe-graphics`** entry. NVIDIA is left unloaded and the panel
runs on the firmware framebuffer, so you land at a **text login prompt** (no
desktop). Log in as `dani` with your password. This entry exists only if you
switched at least once after adding it — if it's missing, use Path 1.

## Path 3 — Fix it headless over SSH (if no console at all)

From your phone or another machine **on your Tailscale network**:

    ssh dani@legionix

The machine brings up networking and sshd even when the GUI is dead, so this
works as long as it booted. Then run the repair commands below.

---

## Once you're at any console

**See what broke:**

    journalctl -b -p err --no-pager | tail -50
    dmesg | grep -i nvidia
    systemctl --failed

**Make it stick — roll back one generation:**

    sudo nixos-rebuild switch --rollback

(If activating live misbehaves because the graphics stack is unhappy, use
`sudo nixos-rebuild boot --rollback` instead, then `reboot`.)

**Or fix the config and rebuild from source:**

    cd ~/nixos-config
    # edit the offending file
    sudo nixos-rebuild boot --flake .#legionix
    reboot

Use `boot`, not `switch`, from a rescue console: it stages the new system
for the next reboot instead of trying to restart the display stack in place.

**List generations (to see what to roll back to):**

    nixos-rebuild list-generations
    # or:
    sudo nix-env --list-generations -p /nix/var/nix/profiles/system

---

## Other tricks

- **GUI frozen but system alive:** switch to a text console with
  `Ctrl+Alt+F2` (through `F6`); come back with `Ctrl+Alt+F1`.
- **Even `safe-graphics` is black:** the firmware framebuffer itself isn't
  coming up. Reseat/replug the external monitor, or enter BIOS with `F2` at
  boot and confirm the graphics mode. This is rare.

---

## Why this works here

There is no usable Intel iGPU on this laptop (BIOS is in discrete-only mode;
the panel is wired straight to the NVIDIA GPU). So `safe-graphics` is a
rescue *console*, not a fallback desktop — enough to read logs and rebuild,
not to keep working in. See `hosts/legionix/gpu.nix` for the specialisation
that defines it.
