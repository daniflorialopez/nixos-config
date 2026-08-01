# System module reference (`modules/nixos/`)

Every shared system module, what it does, the non-obvious choices, and how to
verify it. Hosts opt in by importing these — see the
[module matrix](hosts.md#module-matrix).

---

## base.nix — machine baseline

Timezone (`Europe/Madrid`), locale (`en_US.UTF-8`), NetworkManager, and the
core Nix/boot settings every host shares.

- **Bootloader:** systemd-boot, `timeout = 1` (1s menu — still catchable for
  rollbacks, no every-boot wait), `configurationLimit = 10` boot entries.
- `NetworkManager-wait-online` disabled — nothing at login needs the network,
  so don't block `graphical.target` ~5s waiting for Wi-Fi.
- **zramSwap enabled** — compressed RAM-backed swap. Added after memory spikes
  (VM + desktop + Steam) with no swap hard-locked the machine instead of
  degrading gracefully.
- `programs.fish.enable` (system side; the user shell is set in `users/dani`).
- **Nix housekeeping:** flakes + nix-command enabled, `auto-optimise-store`,
  weekly `nix.optimise`, and **`programs.nh`** with weekly GC
  (`--keep-since 14d --keep 10`). `nh` is the "nix helper" CLI —
  `nh os switch .` is the ergonomic rebuild.
- `system.stateVersion = "25.05"` — **never change** (it pins state-format
  compatibility, not the package version).

**Test:** `nh os switch .` rebuilds; `systemctl status nix-gc.timer` /
`nix-optimise.timer` show the housekeeping timers.

## access.nix — SSH & sudo hardening

- Root account locked (`hashedPassword = "!"`), no root login.
- sudo enabled, `wheelNeedsPassword = true`.
- OpenSSH: `PermitRootLogin = no`, **`PasswordAuthentication = false`**,
  pubkey-only. Firewall opened for sshd.

> This is the *real* sshd. The initrd sshd in `initrd-ssh.nix` is separate and
> **does** allow root (there's no user database before unlock) — don't confuse
> the two.

**Test:** `ssh dani@<host>` works with your key; `ssh root@<host>` is refused.

## security.nix — security tooling

Installs `wireshark` (+ `programs.wireshark.enable` for the capture group) and
`nmap`. Commented placeholders for burp/aircrack/hydra/john when needed (some
need `allowUnfree`/overlays).

## users/dani.nix — the user account

- `mutableUsers = true` — passwords are **not** declarative (kept out of git);
  set with `passwd`.
- User `dani`: groups `wheel networkmanager libvirtd docker gamemode` (gamemode
  renice needs group membership), shell `fish`, two authorized SSH keys
  (`dani@danarchy`, `dani@legionix`).

The initrd sshd (`initrd-ssh.nix`) reuses `authorizedKeys` from here.

## tailscale.nix — mesh VPN

`services.tailscale` with `openFirewall`. Run `sudo tailscale up` once per host
to join. **Backups depend on this** — the restic REST server is reached over
the tailnet, so the waybar tailscale module flags it when down.

## fonts.nix — the one font

Installs the Caskaydia/Cascadia Nerd Font (with a fallback lookup across the
`nerd-fonts` attr names), and enables fontconfig. **CaskaydiaMono Nerd Font is
the only UI/mono font** — terminal, waybar, mako, zathura, SDDM, hyprlock all
name it. See [design-system.md](design-system.md).

## keyd.nix — system-wide key remaps

`services.keyd`, all keyboards (`ids = [ "*" ]`). Remaps **Super+C → Ctrl+Insert**
and **Super+V → Shift+Insert** so Ctrl/Super copy-paste works uniformly across
terminal and GUI apps.

> **Gotcha that bites Hyprland binds:** keyd rewrites Super+C/V *before*
> Hyprland sees them, so any `$mod+V` Hyprland bind is dead. That's why
> clipboard history is on `$mod+P` (`home/dani/wm/hyprland.nix`).

## keyd-vibranium-practice.nix — optional layout drill

A `toggle(vf)` keyd layer (Pause key) remapping querty→a custom "Vibranium"
layout for practice. **Not imported by any host** (commented out in legionix)
— enable when you want to drill the layout.

## corne.nix — split keyboard tooling

QMK/VIA/Vial support for the Corne: `hardware.keyboard.qmk.enable`, tools
(`via qmk qmk-udev-rules usbutils evtest wev`), udev rules for hidraw access
(a Vial-serial-scoped rule for non-root flashing, with a broader VIA fallback
kept commented). legionix only.

## bluetooth.nix — Bluetooth

`hardware.bluetooth` with `powerOnBoot = false` (off until you toggle it from
waybar) and `Experimental = true` for headphone/mouse battery reporting.
`services.blueman` for the GUI pairing manager (opened from the waybar
bluetooth module's right-click). Not on the VM.

## gaming.nix — Steam & performance

- `programs.steam` with **GE-Proton** as a selectable compat tool (eFootball
  freezes at launch on newer stock Proton; GE works).
- `programs.gamemode` — CPU performance governor per-game; opt in with
  `gamemoderun %command%` as a Steam launch option.

## tlp.nix — laptop power management

`services.tlp` (and `power-profiles-daemon` disabled — they conflict). Disables
USB autosuspend both in TLP (`USB_AUTOSUSPEND = "0"`) and at the kernel level
(`usbcore.autosuspend=-1`) — fixes sleeping wireless mice.

## battery-conservation.nix — Lenovo charge cap

This laptop lives docked at the wall, and a Li-ion cell held at 100 % ages from
calendar wear at high voltage even though it barely cycles. The `ideapad_laptop`
driver exposes one toggle at
`/sys/bus/platform/devices/VPC2004:00/conservation_mode`, which on this Legion's
firmware caps charging at **~80 %** (measured 2026-07-29).

- There are **no** `charge_control_*_threshold` nodes on this hardware, so the
  threshold is not tunable and TLP cannot help — this binary toggle is all the
  firmware offers.
- At boot the unit `chgrp wheel` + `chmod g+w` the sysfs node, so the waybar
  click (`conservation-toggle`, `wm/waybar.nix`) can flip it without root, then
  enables conservation — capping at ~80 % is the right daily state for a docked
  machine.
- **Before travel:** click the waybar leaf to allow a full charge and top up.
  It re-enables on the next boot, which is the intended default.
- The `[ -e ]` guard makes the unit a harmless no-op on any host without the
  node.

Verify: `cat /sys/bus/platform/devices/VPC2004:00/conservation_mode` (1 = capped).

## efootball-block.nix — opt-in matchmaking block

Blocks eFootball's **TCP relay** matchmaking path, per session. Matchmaking can
land on direct P2P, peer-server-peer over UDP, or peer-server-peer over TCP;
the TCP relay path is the laggy one. Dropping outbound traffic to its ports
means matchmaking never settles there and falls back to UDP/P2P.

- Ports (`tcp dport { 5736, 30000-35000 }`) are **community-sourced and
  undocumented by Konami**, so they may go stale —
  [source](https://github.com/SuNingXJBT/eFootball_Block_TCP_Matches).
- Its **own nft table** (`inet efb`), not an addition to the NixOS firewall
  ruleset: independent, added and removed atomically, and no need to flip
  `networking.nftables.enable`.
- systemd oneshot + `RemainAfterExit` gives start/stop semantics and free state
  tracking via `systemctl is-active` — which is what the waybar module reads.
- A polkit rule scopes passwordless start/stop of **this one unit** to `wheel`,
  so the waybar click works with no password prompt and without a broad
  NOPASSWD sudoers rule.
- Deliberately **not** `wantedBy = multi-user.target`: the safe default is off
  and a reboot clears it. A 5000-port TCP block left on permanently would
  eventually break something unrelated and be very hard to diagnose.

Imported by the gaming host (`legionix`) only.

## rebuild-ergonomics.nix — see what a rebuild changes

- **Closure diff on every switch.** An activation hook runs `nvd diff` while
  `/run/current-system` still points at the old system, against the one being
  activated — so a plain `sudo nixos-rebuild switch` prints what packages were
  added, removed or changed version. `nh os switch` already does this; the hook
  covers the plain path too. `nvd` is on `PATH` for manual diffs.
- **`check-all`** — builds **every** host plus `nix flake check` before you
  switch. This is a multi-host flake and a change must not break the non-NVIDIA
  host (`danix-hp`) or the VM; this catches that here instead of after a switch.
  Defaults to `~/nixos-config`, or pass a flake path.

## virtualisation.nix — VMs & containers

`libvirtd`, `docker` (pinned `docker_29`), `podman`, and `virt-manager` (GUI).
The `dani` user is in `libvirtd`/`docker` groups (`users/dani.nix`).

## diagnostics.nix — persistent logs

`services.journald.storage = "persistent"` — the journal survives reboots, so
you can investigate a crash after the fact (e.g. the backup post-mortem lives
in the persistent journal).

## hardware-health.nix — SMART monitoring

`services.smartd` with `autodetect`. Background disk-health monitoring; manual
checks in [operations.md](operations.md#disk-health).

## initrd-ssh.nix — remote LUKS unlock

A tiny sshd inside the initrd so a reboot/power-cut away from the machine
doesn't strand it at the passphrase prompt. **Rehearsed in `danixos-vm`;
legionix adds it on LUKS migration day.**

- **Wired network only** — Wi-Fi would need firmware + wpa in the initrd, not
  worth the attack surface. `udhcpc.enable` (NetworkManager hosts don't
  otherwise give the initrd an address); DHCP retries bounded (`-t 2 -T 1`) so
  an undocked laptop only loses ~2–3s before the console prompt.
- **Port 2222** (not 22) so the initrd host key doesn't collide with the real
  sshd's `known_hosts` entry.
- **Root login is fine here** — no user DB exists yet; the shell only exists to
  type the passphrase (`cryptsetup-askpass` appended to `/root/.profile`).
  Reuses `dani`'s `authorizedKeys`.
- **Host key** must be readable *before* unlock, so it lives outside LUKS on
  the ESP. Generate once per host (secret material, not in the repo):
  ```bash
  sudo mkdir -p /etc/secrets/initrd
  sudo ssh-keygen -t ed25519 -N "" -f /etc/secrets/initrd/ssh_host_ed25519_key
  ```
- **Unlock flow:** `ssh -p 2222 root@<host-ip>` → passphrase prompt → boot
  continues (the console prompt keeps working in parallel).

## disko.nix — disk layout (plain btrfs)

Declarative partitioning via disko. Imported by legionix and danix-hp.

- **GPT**, 1 GiB `vfat` ESP at `/boot` (`umask=0077`), rest a single btrfs
  partition named after the host.
- **btrfs subvolumes** (zstd compression, `discard=async`, `autodefrag`):
  - `/root` → `/`
  - `/nix` → `/nix` (`noatime`)
  - `/persist` → `/persist`
  - `/swap` → `/swap` (`noatime`)
  - `/root-blank`, `/snapshots`, `/snapshots/root`, `/snapshots/persist` —
    **scaffolding for future impermanence** (roll `/` back to `/root-blank` on
    boot). Not wired up yet; see [roadmap.md](roadmap.md).
- `/`, `/nix`, `/persist` marked `neededForBoot`.
- `content` is `lib.mkDefault` so a host can override the layout.

## disko-luks.nix — disk layout (LUKS2 + btrfs)

**Identical subvolume layout to `disko.nix`, but the btrfs partition lives
inside a LUKS2 container** (`/dev/mapper/crypted`). Imported by `danixos-vm`;
legionix switches to it on migration day.

- `allowDiscards = true` (SSD TRIM through the crypto layer — leaks only which
  blocks are free, acceptable for a laptop-theft threat model, not forensics)
  and `bypassWorkqueues = true` (faster on NVMe).
- **`passwordFile = "/tmp/disk.key"` is install-time only** — nixos-anywhere
  copies the passphrase there for the initial `luksFormat`
  (`--disk-encryption-keys`). At every real boot the passphrase is typed at the
  console (or over `initrd-ssh`).

## restic.nix — nightly backups

`/home/dani` → a restic REST server over Tailscale, nightly at 20:00.

- Secrets: `restic-password.age` + `restic-env.age` (agenix).
- Excludes caches, Steam, browser caches, `node_modules`, build dirs, `.direnv`,
  `result`, etc.
- `timerConfig`: `OnCalendar = 20:00`, `Persistent` (catches up if the machine
  was off), `RandomizedDelaySec = 30m`.
- Retention (`pruneOpts`): keep 7 daily / 4 weekly / 6 monthly, with
  **`--retry-lock 30m`** (and the same on `extraBackupArgs`) so a concurrent
  manual `restic` run doesn't fail the scheduled prune.
- **Failure alert:** `restic-backups-remote.onFailure` fires
  `restic-backup-failure-notify` — a critical desktop notification **and** a
  line appended to `~/BACKUP-FAILED.txt` (which the waybar backup module turns
  into a red pill).
- **Weekly integrity check** (`restic-check-remote`): `restic check` with
  `--read-data-subset=5%`, so it verifies the repo structure *and* actually
  reads a rotating slice of the data — structure-only checks can pass over
  bit-rotted packs. It routes through the **same** failure-notify path as the
  backup itself, so a check failure surfaces as the same red pill; a backup
  that runs nightly but silently restores nothing is the failure mode this
  exists to catch.

Day-to-day commands and the restore test: [operations.md](operations.md#backups-restic).

---

## desktop/ — display manager & desktop environments

Imported through `hosts/<host>/desktop.nix`.

### desktop/sddm.nix — login greeter

SDDM (Qt6, `kdePackages.sddm`) with a **Tokyo Night-recolored `sddm-astronaut`
theme** — frosted center column over the same mountain-sunset wallpaper
hyprlock and the desktop use, so login → lock → desktop is one continuous
scene. Blue accents, orange only on hover (the shared role rule — see
[design-system.md](design-system.md)).

- **`wayland.enable = false` (X11 greeter) on purpose:** the Wayland greeter
  (weston kiosk) stacks every window on one output (laptop panel goes black)
  and kwin is unstable on the closed NVIDIA driver. The X11 greeter reliably
  places one window per screen. **Only the greeter is X11 — the Hyprland
  session stays Wayland.**
- Bibata cursor matches the desktop (`home/dani/wm/cursor.nix`).
- `services.xserver.enable = true` here is also what Cinnamon (X11) needs.

### desktop/hyprland.nix — Hyprland (system side)

Enables `programs.hyprland` (`withUWSM = true`, xwayland on). Also:
`programs.dconf` (GTK dark preference), a PAM service for **hyprlock**
(without it hyprlock can't validate the password), Wayland `xdg.portal`
(hyprland + gtk backends), and `NIXOS_OZONE_WL = "1"` (Electron on Wayland).
The user-side Hyprland config is `home/dani/wm/hyprland.nix`.

### desktop/cinnamon.nix — fallback DE

`services.xserver.desktopManager.cinnamon.enable`. The selectable fallback
session in the greeter, and the *only* desktop on the VM.
