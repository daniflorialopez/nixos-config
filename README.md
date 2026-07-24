# Dani's NixOS + Home Manager config

Flake-based NixOS configuration for all my machines. One flake builds every
host; each host is a thin list of shared modules plus its hardware. The
system layer (`modules/nixos/`) and the user layer (Home Manager,
`home/dani/`) are wired together so the same config produces the same
desktop on every machine — and so the VM (`danixos-vm`) is a faithful
rehearsal ground for changes before they touch the real laptop.

Highlights: disko-managed btrfs partitioning, agenix secrets, nightly
restic backups, Hyprland desktop with a hand-tuned Tokyo Night design
system, and a staged (not-yet-live) LUKS + remote-unlock migration.

## Hosts

| Host         | Machine              | Role & notes                                                                 |
| ------------ | -------------------- | ---------------------------------------------------------------------------- |
| `legionix`   | Lenovo Legion laptop | **Main machine.** NVIDIA GPU, Hyprland, restic backups, Corne keyboard.      |
| `danix-hp`   | HP laptop            | Secondary. ⚠ `disko.devices.disk.main.device` is **not set** — fill it in before installing. |
| `danixos-vm` | libvirt VM           | Test bed. Runs the **LUKS + initrd-SSH rehearsal** for the legionix migration. |

## Repo layout

```
flake.nix              inputs + one nixosConfiguration per host (via mkHost)
flake.lock             pinned input revisions
hosts/<host>/          host entry point:
  default.nix            imports hardware + the modules this host wants
  hardware-configuration.nix   machine-specific, generated (never copied)
  desktop.nix / gpu.nix  host-local extras
modules/nixos/         shared SYSTEM modules (disko, restic, tailscale, keyd…)
  desktop/               display manager + desktop-environment modules
  users/dani.nix         the user account
home/dani/             Home Manager (USER) config
  shell/                 fish, starship, alacritty, tmux, zellij, btop, CLI tools
  programs/              GUI apps, browsers, dev tools, file associations
  wm/                    Hyprland, waybar, walker, clipboard, lock, theme…
  assets/wallpapers/     wallpaper images
secrets/               agenix-encrypted .age files + secrets.nix recipient list
docs/                  ← full documentation (this README is the map)
```

## Documentation map

Start here, then jump to the file you need. Every module and every home file
is documented — you should never have to reverse-engineer what a `.nix` file
does from the code alone.

| Doc                                       | What's in it                                                                 |
| ----------------------------------------- | ---------------------------------------------------------------------------- |
| [docs/architecture.md](docs/architecture.md) | How the flake wires up: inputs, `mkHost`, the system↔home bridge, stable/unstable pkgs. **Read this first.** |
| [docs/install.md](docs/install.md)        | Fresh-install runbook (nixos-anywhere + disko), new-host checklist, first-boot steps. |
| [docs/hosts.md](docs/hosts.md)            | Per-host breakdown + a table of which module each host imports.              |
| [docs/modules.md](docs/modules.md)        | Reference for **every** file in `modules/nixos/` — purpose, key options, how to test. |
| [docs/home.md](docs/home.md)              | Reference for **every** file in `home/dani/` — shell, programs, WM.         |
| [docs/design-system.md](docs/design-system.md) | The Tokyo Night palette and the role rules (blue = accent, orange = attention-only, slate borders) every app follows. |
| [docs/operations.md](docs/operations.md)  | Day-to-day: rebuilding, backups, secrets, disk health, garbage collection, testing a change. |
| [docs/luks-runbook.md](docs/luks-runbook.md) | **Copy-paste LUKS runbook** — remote unlock, the three recovery drills, and the legionix migration-day sequence. The source of truth when reinstalling with encryption. |
| [docs/roadmap.md](docs/roadmap.md)        | Staged work (LUKS status, impermanence), known issues, and install post-mortems.   |

## Quick start

```bash
# Rebuild the current machine after editing config (nh = nix helper)
sudo nixos-rebuild switch --flake .#<host>
#   or:  nh os switch .        (nh picks the host from hostname)

# Build without switching (safe dry run of the evaluation + build)
nixos-rebuild build --flake .#<host>

# Update all flake inputs, then rebuild
nix flake update && sudo nixos-rebuild switch --flake .#<host>

# Edit a secret (needs your ~/.ssh key listed in secrets/secrets.nix)
cd secrets && nix run github:ryantm/agenix -- -e restic-env.age

# Check backups
sudo restic-remote snapshots
```

New machine? See [docs/install.md](docs/install.md). Testing a risky change
(LUKS, disko)? Rehearse it in `danixos-vm` first — see
[docs/operations.md](docs/operations.md#testing-a-change).
