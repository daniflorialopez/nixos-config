# Design system — Tokyo Night, with rules

Almost every home file carries color config, and they all obey the same small
set of rules. Understand these once and every theme block in the repo reads the
same way — and you'll know how to add a new app without it clashing.

## The palette

Tokyo Night (moon family). The canonical named-role definition lives in
`home/dani/wm/theme.nix` as `waybar/palette.css`; the terminal 16-color source
of truth is `home/dani/shell/alacritty.nix`. Everything else mirrors these.

| Hex        | Name / role        | Used for                                             |
| ---------- | ------------------ | ---------------------------------------------------- |
| `#1a1b26`  | bg                 | Base background everywhere                            |
| `#24283b`  | surface / bg-alt   | Raised surfaces (input fields, inactive tabs)        |
| `#283457`  | selection wash     | Selection / hover background (keeps text readable)   |
| `#c0caf5`  | fg                 | Primary foreground text                              |
| `#a9b1d6`  | subtle             | Secondary text                                       |
| `#a0a5c0`  | muted (AAA)        | "Dim" text, lightened from canon for legibility      |
| `#565f89`  | slate / muted-line | **Borders, inactive frames, comments**               |
| `#7aa2f7`  | **accent (blue)**  | **The accent. Active frames, highlights, selection** |
| `#ff9e64`  | **attention (orange)** | **"Look here" / needs-you ONLY** (see rule)      |
| `#e0af68`  | warning (yellow)   | Warnings, session name, gradient midpoint            |
| `#9ece6a`  | success (green)    | Success, valid, "healthy" (`b9f27c` = bright green)  |
| `#f7768e`  | critical (red)     | Errors, alerts (`f88298` = AAA-lightened text red)   |
| `#bb9af7`  | purple             | vi visual mode, remote-session marker, escapes       |
| `#4fd6be`  | teal ("cyan")      | Cached memory; teal *on purpose* (see no-cyan rule)  |

## The rules

These are the choices that keep 15 different apps looking like one system.

### 1. Blue is the accent; orange is attention-only

On a dark surface, the **active/selected** thing takes **blue** (`#7aa2f7`) —
active pane frame, active tab, focused workspace pill, selection. **Orange**
(`#ff9e64`) is reserved for the *attention tier*: "look here" or "this needs
you". Nothing wears orange just for being active.

Where orange legitimately appears: waybar's urgent workspace + the backup-failed
pill, zellij's `frame_highlight` (resize/search), btop's load graphs, search-hit
highlights (yazi/zathura/fzf), the hyprlock password ring. Two things
recently *left* the orange tier and joined the neutral slate:

- **Hyprland window borders** (2026-07-22): the old sunset gradient painted a
  different hue per edge and read as noise. Now active = slate `#565f89`,
  inactive = near-invisible. Focus is signaled by **value, not hue** —
  "Windows-calm".
- **Walker's popup frame** (2026-07-24): a launcher is user-invoked chrome, not
  an alert, so it wears slate too.

### 2. The sunset gradient means "load / attention", nowhere else

`yellow → orange → red` (`#e0af68 → #ff9e64 → #f7768e`) is the load/attention
gradient. It lives on btop's cpu/memory/temp graphs and the hyprlock ring —
things that escalate. It is *not* decoration.

### 3. No cyan in prompts; teal is deliberate

Dani can't quickly distinguish cyan from blue/white, so the prompt (starship)
and fish use **no cyan** — its roles went to sunset orange (maximum hue
distance from blue). Where "cyan" survives (alacritty, btop cached memory) it's
rendered as **teal** `#4fd6be`, distinct enough to read.

### 4. Contrast is calibrated to WCAG AAA (≥7:1 on `#1a1b26`)

Several values are lightened from Tokyo Night canon so text is legible:
`muted` `#a0a5c0` (canon `#787c99` was ~4.2:1), fish/alacritty `bright black`
`#737aa2` (canon `#444b6a` was nearly invisible at ~2.5:1), the AAA reds
`#f88298`, greens `#b9f27c`, blue `#7ea5f7`. Same hues, raised lightness.
`#737aa2` is the contrast **floor** for hint/placeholder text.

### 5. One font: CaskaydiaMono Nerd Font

Terminal, waybar, mako, zathura, imv, SDDM, hyprlock, walker, lazygit all name
it (`modules/nixos/fonts.nix` installs it). Note in-repo: Caskaydia's capitals
have flat-cut apexes by design — they can look "cropped" at list sizes, which
is why walker uses regular (not semibold) weight for list items.

## Where each surface gets its color

| Surface                     | File                              |
| --------------------------- | --------------------------------- |
| Named-role palette (GTK)    | `wm/theme.nix` → `waybar/palette.css` |
| Terminal 16-color (source)  | `shell/alacritty.nix`             |
| Shell prompt                | `shell/starship.nix`              |
| Shell syntax + fzf          | `shell/fish.nix`                  |
| tmux / zellij / btop        | `shell/{tmux,zellij,btop}.nix`    |
| Launcher                    | `wm/walker.nix`                   |
| Status bar                  | `wm/waybar.nix` (+ palette.css)   |
| Notifications               | `wm/hyprland-services.nix` (mako) |
| Window borders / glass      | `wm/hyprland.nix`                 |
| Lock screen                 | `wm/hyprlock.nix`                 |
| Login greeter               | `modules/nixos/desktop/sddm.nix`  |
| PDF / images                | `programs/apps.nix` (zathura/imv) |
| Git TUI                     | `programs/devtools.nix` (lazygit) |
| File manager (TUI)          | `programs/yazi.nix`               |

## Adding a new app without clashing

1. Background `#1a1b26`, text `#c0caf5`, secondary `#a9b1d6`/`#a0a5c0`.
2. Active/selected → blue `#7aa2f7`; selection background → `#283457`.
3. Borders/inactive → slate `#565f89`.
4. Reserve orange `#ff9e64` for genuine "look here" states only.
5. Green success, red error, yellow warning; avoid cyan (use teal if forced).
6. Font: `CaskaydiaMono Nerd Font`.
7. Check text contrast ≥7:1 on `#1a1b26`; lighten the hue if short.
