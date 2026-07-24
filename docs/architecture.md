# Architecture

How this repo turns a handful of `.nix` files into a running machine. Read
this before the per-file references — once the wiring is clear, every other
doc is just detail.

## The big picture

```
flake.nix
   │  mkHost "legionix"
   ▼
hosts/legionix/default.nix ──imports──► modules/nixos/*.nix   (SYSTEM layer)
   │                                     hosts/legionix/{desktop,gpu}.nix
   │
   └── flake.nix also injects, for every host:
         • agenix          (secrets at activation time)
         • home-manager    (as a NixOS module)
                │
                ▼
         home/dani/default.nix ──imports──► home/dani/{shell,programs,wm}/*  (USER layer)
```

Two layers, one build:

- **System layer** — `modules/nixos/` and the `hosts/` entry points. Anything
  that needs root or affects the whole machine: bootloader, disks, drivers,
  services, users, the display manager. Documented in
  [modules.md](modules.md) and [hosts.md](hosts.md).
- **User layer** — `home/dani/`. Everything inside Dani's session: shell,
  terminal, editor, the Hyprland desktop and its chrome, GUI apps, theming.
  Managed by Home Manager but built in the same `nixos-rebuild`. Documented
  in [home.md](home.md).

## flake.nix

### Inputs

| Input                | Purpose                                                                 |
| -------------------- | ----------------------------------------------------------------------- |
| `nixpkgs`            | Main package set, pinned to the **`nixos-25.11`** release branch.       |
| `nixpkgs-unstable`   | Unstable channel, imported ad-hoc for a few packages that need to be newer than release (Claude Code, waytrogen, hyprpaper). See [stable vs unstable](#stable-vs-unstable-packages). |
| `home-manager`       | User-environment manager, following `release-25.11` to match nixpkgs.   |
| `nixos-hardware`     | Hardware quirk profiles (available; wire in per-host as needed).        |
| `disko`              | Declarative disk partitioning. Used by `modules/nixos/disko*.nix`.      |
| `agenix`             | Age-encrypted secrets, decrypted at activation with the host SSH key.   |
| `walker` + `elephant`| Application launcher and its data-provider backend (`home/dani/wm/walker.nix`, `clipboard.nix`). `walker` follows the same `elephant`. |
| `nix-index-database` | Prebuilt `nix-index` DB powering `comma` (run any binary without installing). |
| `lazyvim-starter`    | LazyVim starter config, seeded once into `~/.config/nvim` (`flake = false`, i.e. a plain source tree, not a flake). |

### mkHost

Every host is built by one helper so they stay symmetric:

```nix
mkHost = name: nixpkgs.lib.nixosSystem {
  inherit system;                       # x86_64-linux
  specialArgs = { inherit inputs; };    # modules can read `inputs`
  modules = [
    ./hosts/${name}                     # the host's own config
    inputs.agenix.nixosModules.default  # secrets
    home-manager.nixosModules.home-manager
    { /* home-manager wiring, see below */ }
  ];
};

nixosConfigurations = {
  danixos-vm = mkHost "danixos-vm";
  danix-hp   = mkHost "danix-hp";
  legionix   = mkHost "legionix";
};
```

Keeping the wiring in one place is deliberate: it means the VM really does
mirror the real machines, which is what makes the LUKS rehearsal in
`danixos-vm` trustworthy (see [roadmap.md](roadmap.md)).

`specialArgs = { inherit inputs; }` is why system modules can write
`{ inputs, ... }:` and reach flake inputs directly (e.g. `disko.nix` importing
`inputs.disko.nixosModules.disko`, `restic.nix` using the agenix package).

### Home Manager as a NixOS module

The inline module in `flake.nix` mounts Home Manager inside the system build:

```nix
home-manager.useGlobalPkgs = true;       # HM uses the system's nixpkgs
home-manager.useUserPackages = true;     # user pkgs into /etc profiles
home-manager.sharedModules = [ nix-index-database.homeModules.default ];
home-manager.backupFileExtension = "hm-backup";  # conflicting files → *.hm-backup
home-manager.extraSpecialArgs = { inherit inputs; };  # home modules see `inputs` too
home-manager.users.dani = import ./home/dani;
```

Consequences worth knowing:

- **One rebuild does both layers.** `nixos-rebuild switch` builds system *and*
  home; there is no separate `home-manager switch`.
- If Home Manager wants to write a dotfile that already exists and isn't
  managed, it renames the old one to `*.hm-backup` instead of failing. If a
  rebuild dies on a "would be clobbered" error, look for that.
- `extraSpecialArgs` is why home modules can write `{ inputs, ... }:`
  (e.g. `devtools.nix` importing `nixpkgs-unstable`, `walker.nix` importing
  the walker HM module).

## The system ↔ home bridge (`osConfig`)

`home/dani/default.nix` conditionally loads the desktop only when the host
actually enables Hyprland:

```nix
hyprEnabled = osConfig != null && (osConfig.programs.hyprland.enable or false);

imports = [ ./shell ./programs ]
  ++ lib.optionals hyprEnabled [ ./wm/hyprland.nix ./wm/wallpaper.nix ];
```

`osConfig` is the **system** configuration, made visible to home modules
because Home Manager runs as a NixOS module. So a headless or Cinnamon-only
host (like the VM, which imports no Hyprland module) gets the shell and
programs but **not** the Hyprland/waybar/walker stack. This is the single
switch that keeps `home/dani/` portable across graphical and non-graphical
hosts.

`home/dani/wm/hyprland.nix` then imports the rest of the desktop
(`hyprland-services.nix`, `clipboard.nix`, `hyprlock.nix`, `theme.nix`,
`walker.nix`, `waybar.nix`, `cursor.nix`), so the whole WM layer hangs off
that one conditional import.

## Import chains

Nix modules compose by `imports`. The chains here:

- **System:** `hosts/<host>/default.nix` lists every `modules/nixos/*.nix` it
  wants, plus `./desktop.nix` (which imports `modules/nixos/desktop/*`).
- **Home:** `home/dani/default.nix` → `./shell` and `./programs` (each a
  `default.nix` that imports its siblings) → conditionally `./wm/hyprland.nix`
  (which imports the rest of `wm/`).

To add a feature you almost always: write a new `.nix` file in the right
layer, then add it to the nearest `default.nix`'s `imports` (or a host's
import list, if it should be per-host).

## Stable vs unstable packages

The default package set is the pinned `nixos-25.11` release. A few packages
need to be newer, so modules import `nixpkgs-unstable` locally rather than
switching the whole system to unstable:

```nix
# home/dani/programs/devtools.nix
unstablePkgs = import inputs.nixpkgs-unstable {
  system = pkgs.stdenv.hostPlatform.system;
  config.allowUnfree = true;              # Claude Code is unfree
};
# … then use unstablePkgs.claude-code
```

Also used this way: `waytrogen` and `hyprpaper` in `home/dani/wm/wallpaper.nix`
and `hyprland-services.nix` (via `inputs.nixpkgs-unstable.legacyPackages.*`).
Everything else comes from the pinned release. When something misbehaves after
an update, check whether it's a stable or an unstable package first.

## Where state lives

- **Declarative** (in this repo): everything above.
- **Mutable, seeded once:** `~/.config/nvim` — the LazyVim starter is copied in
  on the first rebuild and then left alone so your plugin edits survive (see
  [home.md](home.md#devtoolsnix) for the marker-file mechanism).
- **Runtime state, not in git:** wallpaper selection
  (`~/.local/state/wallpaper/…`), clipboard history
  (`~/.cache/elephant/clipboard.gob`), the initrd SSH host key
  (`/etc/secrets/initrd/…`, generated per-host).
- **Secrets:** encrypted in `secrets/*.age`, decrypted at activation into
  `/run/agenix/…`. See [operations.md](operations.md#secrets-agenix).
