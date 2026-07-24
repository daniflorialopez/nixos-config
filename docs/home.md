# Home Manager reference (`home/dani/`)

Everything inside Dani's session. Loaded via `home-manager.users.dani =
import ./home/dani` in `flake.nix`. The desktop (`wm/`) only loads on hosts
that enable Hyprland — see the [osConfig bridge](architecture.md#the-system--home-bridge-osconfig).

```
home/dani/
  default.nix     entry point; imports shell + programs, conditionally wm/
  shell/          terminal, shell, multiplexers, monitoring
  programs/       GUI apps, browsers, dev tools, file associations
  wm/             Hyprland desktop and its chrome
  assets/         wallpapers
```

`default.nix` sets `home.username`/`homeDirectory`/`stateVersion` (`25.05`,
don't change) and gates `./wm/hyprland.nix` + `./wm/wallpaper.nix` on
`hyprEnabled`.

---

## shell/

`shell/default.nix` imports all of the below.

### cli.nix — CLI toolbox

The everyday command-line packages: modern coreutils (`eza fd ripgrep fzf
zoxide jq yq tree`), monitoring (`htop lsof ncdu strace ltrace gdu
smartmontools`), networking (`mtr nmap iperf3 dnsutils socat …`), transfer
(`rsync`), `gnupg`, `git`, PDF tools (`poppler-utils qpdf`), etc. Also:

- **`programs.bat`** with `theme = "ansi"` — maps bat's syntax colors onto the
  terminal's calibrated Tokyo Night 16-color palette instead of its default
  Monokai (which fights the scheme).
- Session vars: `EDITOR`/`VISUAL = nvim`, `PAGER`/`MANPAGER = less -R`.

### fish.nix — shell + fzf

- **`programs.fzf`**: `fd`-based default command, Tokyo Night colors (orange
  match highlight, blue prompt, `#283457` selection wash), reverse history
  widget. Fish integration is sourced manually last (`shellInitLast`).
- **`programs.fish`**:
  - Abbrs (`gs ga gcm gl`) and aliases (`n=nvim ll=eza… lg=lazygit`), plus
    `*-run` abbrs for running non-Comma-friendly nixpkgs binaries.
  - A custom `fish_greeting` — a Tokyo Night `╭─ user@host · role · shell`
    banner that detects SSH sessions (remote → purple).
  - `interactiveShellInit`: `fish_vi_key_bindings`, zoxide init, and the
    **WCAG-AAA-calibrated Tokyo Night syntax colors** (same hues as canon,
    lightness raised to ≥7:1 on `#1a1b26`). See [design-system.md](design-system.md).

### starship.nix — prompt

Minimal two-part prompt: `$directory$git_branch$git_status$character`. Locks a
`tokyo_night` palette so named colors don't drift with the terminal.
Deliberately **no cyan** (Dani can't distinguish it fast from blue/white — its
roles go to sunset orange) and most language/context modules disabled for a
quiet prompt. The `❯` is orange, error `✗` red, vim-mode `❮` green/purple/red.

### alacritty.nix — terminal

The **source of truth for the 16-color terminal palette** everything else
mirrors. CaskaydiaMono font, `opacity = 0.96` (glass), `#283457` selection
wash. Notable calibration notes in-file: `cyan` is intentionally teal
(tokyonight-moon family), `bright black` lightened from canon so "muted" CLI
text is legible. Super+C/V and Ctrl/Shift+Insert copy-paste bindings;
`osc52 = "OnlyCopy"` for remote-copy.

### tmux.nix — tmux + Oh My Tmux

tmux with **Oh My Tmux** pinned by commit hash (`fetchFromGitHub`). Sensible
defaults (mouse, vi keys, 100k history, `escapeTime 0`, base index 1).
Nix-managed plugins (no TPM): `resurrect` + `continuum` (auto-save/restore
sessions every 15 min), `yank`, `extrakto`, `vim-tmux-navigator`. Prefix
changed to **Ctrl-Space** in `~/.tmux.conf.local` (HM-managed), plus the Tokyo
Night colour-slot remap.

### zellij.nix — zellij

Alternative multiplexer with a fully-explicit `tokyo-sunset` theme (every UI
element mapped, rather than letting zellij pick). Design rule made concrete:
dark surface → blue accent (active frame/tab), orange only as the attention
pop (`frame_highlight`), green for success exit codes, red for errors.

### btop.nix — system monitor

btop with a custom `tokyo-sunset.theme`, transparent background (inherits
Alacritty's glass), vim keys. The graphs that mean "load" (cpu, temp, used
memory, upload) climb the **sunset gradient** (yellow→orange→red, same as the
Hyprland active border used to be); free memory stays green, cached goes teal,
download is the blue family.

---

## programs/

`programs/default.nix` imports all of the below.

### apps.nix — viewers & file tooling

- **`programs.zathura`** (PDF, mupdf plugin) — full Tokyo Night recolor;
  `recolor = true` renders pages dark by default (Ctrl+R → paper white for
  print-faithful reading). Search hits: orange = "look here", blue = active
  hit (the shared find/position split).
- **imv** config (dark canvas + palette overlay) via `xdg.configFile`.
- Packages: `pcmanfm file-roller okular imv mpv libreoffice`, plus yazi's
  preview deps (`ffmpeg p7zip poppler-utils imagemagick fd ripgrep fzf
  zoxide …`).

### browsers.nix — browser packages

`google-chrome`, `ungoogled-chromium`, `brave`. (Firefox is configured
separately in `firefox.nix`.)

### firefox.nix — Firefox

`programs.firefox` with three profiles — **personal** (default), **work**,
**lab** — each dark-by-default (`prefers-color-scheme` overridden to dark).
Policy-installed extensions: uBlock Origin, Vimium, Auto Tab Discard. Bound to
`$mod+B` / `$mod SHIFT+B` / `$mod CTRL+B` in Hyprland.

### bitwarden.nix — password CLI

Just `bitwarden-cli` (`bw`). Pipe secrets to `pwcopy` (see
[clipboard.nix](#clipboardnix)) to copy without recording in history.

### comma.nix — run anything

`programs.nix-index` + the `nix-index-database` `comma` integration, so
`, <binary>` runs any packaged program without installing it.
`COMMA_CACHING = "1"`.

### devtools.nix — editor & dev environment

- Packages: **`claude-code` (from nixpkgs-unstable)**, `obsidian`, `vscodium`,
  `jetbrains.idea`, `python3`, `virt-manager`.
- **`programs.lazygit`** — Tokyo Night theme (blue active border, orange only
  for search, `#283457` selection).
- **`programs.git`** — name/email + LFS.
- **`programs.neovim`** — `defaultEditor`, vi/vim aliases, and the runtime
  tools LazyVim expects (ripgrep, fd, fzf, treesitter deps: nodejs,
  tree-sitter, cc, make; clipboard: wl-clipboard, xclip).
- **LazyVim seeding (the subtle part):** two `home.activation` hooks —
  1. `lazyvimStarter` copies the `lazyvim-starter` flake input into a
     **writable** `~/.config/nvim` **once**, guarded by a marker file
     (`.seeded-by-nix-lazyvim`). It does **not** re-sync on later rebuilds, so
     your plugin edits and `lazy-lock.json` survive. Delete the marker to
     re-seed from upstream.
  2. `lazyvimNixOverrides` appends `pcall(require, "config.nix")` to
     `options.lua`/`init.lua`, loading the HM-generated
     `nvim/lua/config/nix.lua` (currently just `clipboard = "unnamedplus"`).

### media.nix — media apps

`kdenlive`, `obs-studio`, `spotify`.

### misc.nix — leftovers

`restic` (client), `libreoffice`, `pcmanfm`, `vesktop` (Discord), `warpd`
(modal keyboard-driven mouse control, Wayland-capable).

### whatsapp.nix — WhatsApp Web PWA

A `writeShellApplication` wrapper launching Chromium in `--app` mode against
web.whatsapp.com with a **dedicated profile dir** (`~/.local/share/
chromium-whatsapp`). Ships a desktop entry and a `$mod SHIFT+W` Hyprland bind.

### yazi.nix — terminal file manager

`programs.yazi` with a Tokyo Night theme and a full **opener/rule table**:
per-extension and per-MIME rules routing files to nvim / zathura+okular / imv /
mpv / LibreOffice / file-roller. The single place that decides "what opens what"
*inside* yazi (the desktop-wide equivalent is `mimeapps.nix`).

### mimeapps.nix — desktop file associations

The **system-wide** "what opens what": defines hidden handler `.desktop`
entries (nvim-in-Alacritty for text/code, firefox, pcmanfm, zathura, okular,
imv, mpv, LibreOffice calc/writer/impress, file-roller) and maps a large
`defaultApplications` table of MIME types to them. Text/code files open in
Neovim inside Alacritty; PDFs default to zathura with okular as an
"Open With" alternative.

---

## wm/ — the Hyprland desktop

Loaded only on Hyprland hosts. `wm/hyprland.nix` is the hub that imports the
rest.

### hyprland.nix — window manager

The core Hyprland config plus two generated helper scripts:

- **`screenshot-satty`** — `slurp` region select (orange selection box) →
  `grim` → `satty` editor, saved to `~/Pictures/Screenshots` and copied. Bound
  to `Print`.
- **`keybinds-menu`** (`$mod+/`) — a searchable keybind palette. Reads the
  **live** binds from `hyprctl binds -j`, decodes modmasks, groups them under
  topic headers (Apps/Clipboard/Workspaces/Focus/Windows/Media/System), merges
  duplicate chords (vim keys + arrows) and collapses the ten per-digit
  workspace binds into one row, then renders through walker's dmenu and
  dispatches the chosen bind. Because it reads live binds, it also documents
  binds declared in other files (e.g. `whatsapp.nix`, `wallpaper.nix`).

Config highlights:

- **Monitors:** `HDMI-A-1` (external, left) + `eDP-1` (laptop panel, right).
  Workspaces 1/4/5–10 pinned to the external, 2–3 to the panel. Adjust the
  `monitor` list + `workspace` bindings on a machine with different outputs.
- **Every bind is `bindd`** (bind + description) so it shows up meaningfully in
  the `$mod+/` palette. Layout: vim keys **and** arrows for focus/move/resize,
  `$mod`+digit workspaces, media/brightness keys, app launchers
  (`Return`=terminal, `Space`=walker, `M`=files, `B`=firefox profiles, …).
- **`$mod+P` = clipboard history** (not V — keyd steals Super+V, see
  [keyd.nix](modules.md#keydnix)). `$mod+Escape` = hyprlock.
- **Look:** slate borders (active `#565f89`, inactive near-invisible) —
  **the sunset gradient was removed from borders** in a 2026-07-22 A/B; focus
  is signaled by value not hue. Glass everywhere (opacity 0.94/0.88 + light
  blur), rounding 12, shadows. Media windows (mpv/imv/zathura/satty/OBS/PiP)
  forced to full opacity so video/PDFs stay true-color.
- `layerrule` blurs the chrome (waybar/walker/mako). UWSM env
  (`~/.config/uwsm/env-hyprland`) pins the DRM device.

Full keybind list: press `$mod+/` on a running machine, or read the `bindd`
block. See also [design-system.md](design-system.md) for the color rationale.

### hyprland-services.nix — session services

User systemd services bound to the graphical session:

- **mako** — notifications, Tokyo Night styled (blue border; low=slate,
  critical=red), `default-timeout = 0` (persist until dismissed via `$mod+'`).
- **hyprsunset** — night-time warmth: identity by day (keeps the calibrated
  palette true), 4200 K at 21:00, 3700 K at 23:30.
  `hyprctl hyprsunset identity` overrides it for color-sensitive night work.
- **polkit-gnome-agent** — auth dialogs.
- Also re-adds the **gtk portal backend** (the walker HM module otherwise
  narrows `xdg.portal` to hyprland-only, which breaks the dark preference for
  GTK4 apps like pavucontrol).

### wallpaper.nix — wallpaper management

hyprpaper (user service) reading a state file
(`~/.local/state/hypr/hyprpaper-selected.conf`) that a `wall-apply` script
rewrites. `wall-picker` (`$mod CTRL+W`) launches **waytrogen** to pick from
`~/Pictures/Wallpapers` (synced from `assets/wallpapers/`) and applies to both
monitors with a fit mode. waytrogen/hyprpaper come from nixpkgs-unstable.

### waybar.nix — status bar

Three **floating glass islands** (left/center/right), Tokyo Night via
`palette.css`. Modules are **silent when healthy**:

- `custom/backup` — invisible unless `~/BACKUP-FAILED.txt` has content, then a
  blinking red pill (click = open log, right-click = acknowledge/truncate).
  The one loud thing on the bar, and only when earned.
- `custom/tailscale` — dim while up (glanceable confirmation, since 20:00
  backups need it), red when down.
- `custom/gpu` — NVIDIA temp on legionix; self-hides elsewhere.
- `mpris` — appears only while media plays.
- `custom/kblayout` — US/ES layout, click to cycle.
- `bluetooth` (click toggles, clearing the ideapad rfkill soft-block; right =
  blueman), `network` (right = nm-connection-editor), `pulseaudio`, `battery`,
  `tray`, workspaces, window title.
- Also hides the duplicate nm-applet/blueman **tray autostart** entries (the
  bar's own modules cover both).

### walker.nix — launcher

The `walker` launcher + `elephant` provider backend. Providers: desktop apps,
runner, calc, clipboard, windows, symbols. Prefix routing (`;` provider list,
`>` run, `=` calc, `:` clipboard, `.` symbols, `$` windows). Custom
`dani-soft` Tokyo Night GTK theme — **slate popup frame** (joined the neutral
tier 2026-07-24; orange means "needs you", and a launcher doesn't). `$mod+Space`
opens it; `$mod+P` opens it in clipboard mode.

### clipboard.nix — clipboard hygiene

Elephant clipboard history hardening (the [system-improvement](roadmap.md)
"clipboard hardening" item):

- `elephant/clipboard.toml` — `auto_cleanup = 720` (12 h TTL *and* sweep
  interval), `max_items = 100`. The history db is plaintext
  (`~/.cache/elephant/clipboard.gob`) — the TTL bounds exposure until the disk
  is LUKS-encrypted.
- **`pwcopy`** — copy a secret from stdin *without* recording it: pauses the
  elephant recorder around the copy (a real guarantee — missed events aren't
  re-scanned on unpause), notifies, and auto-clears the live clipboard after
  45 s. Usage: `bw get password <item> | pwcopy`.
- **`clipboard-wipe`** (`$mod SHIFT+P`) — panic button: empties history + live
  clipboard (for secrets that arrived outside pwcopy, e.g. the Firefox
  Bitwarden extension).

### hyprlock.nix — lock screen

hyprlock over a blurred screenshot (matches whatever wallpaper is active),
sunset-gradient ring on the password field, big clock + "Saturday 18 July"
date (same wording as the SDDM greeter and waybar). Needs
`security.pam.services.hyprlock` on the system side
([desktop/hyprland.nix](modules.md#desktophyprlandnix-hyprland-system-side)).
**No idle auto-lock by choice** — locking is manual (`$mod+Escape`). hypridle
only locks before suspend and restores displays after resume.

### theme.nix — GTK/Qt theming + the palette source

- GTK (`adw-gtk3-dark` + Papirus-Dark icons, dark preference for GTK3/4),
  libadwaita via dconf `color-scheme = prefer-dark`, Qt via `adwaita-dark`.
- **`waybar/palette.css`** — the shared Tokyo Night GTK color variables
  (`@accent`, `@attention`, `@critical`, …) that waybar imports. The canonical
  named-role palette; see [design-system.md](design-system.md).

### cursor.nix — cursor theme

`Bibata-Modern-Ice`, size 32, for GTK + `home.pointerCursor` (SDDM names the
same cursor so it's continuous from login).
