# Design system — Tokyo Night, with rules

Almost every home file carries color config, and they all obey the same small
set of rules. Understand these once and every theme block in the repo reads the
same way — and you'll know how to add a new app without it clashing.

## The palette

Tokyo Night (moon family). The canonical definition is
**`home/dani/theme/palette.nix`** — one attrset of named roles, each tiered, with
views for every syntax the repo needs (`#rrggbb`, `0xrrggbb`, bare `rrggbb` for
fish, and the two different `rgba()` spellings Hyprland and GTK use).
`waybar/palette.css` is generated from it. Migration of the remaining consumers
is tracked in `docs/ricing/08-implementation-tracker.md`; until each one lands,
its literals are still hand-written.

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
  different hue per edge and read as noise. Focus is signaled by **value, not
  hue** — "Windows-calm".

  Refined 2026-09-18 in a second live A/B: the flat active slate became a
  two-stop **value ramp inside one hue**,
  `rgba(737aa2ff) rgba(3b4261ff) 45deg`. This is the July rule taken further,
  not reversed — what July rejected was a *hue* gradient; both stops here are
  slate and both already exist in the palette (`#737aa2` is the hint-text
  contrast floor, `#3b4261` the inactive gutter at full alpha). The focused
  frame now reads as a lit bevel and is brighter overall than the `#565f89` it
  replaced, so focus is more legible rather than merely different. Inactive is
  unchanged at `rgba(3b426188)`.

  Gradients interpolate in **OkLab**, so the midpoint stays in the slate family
  instead of going muddy. Never combine with `borderangle ... loop` — it pins
  both panels at full refresh permanently, even when no gradient border is
  visible.
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

### 4. Contrast is calibrated, and now enforced at build time

Body text clears **WCAG AAA (≥7:1 on `#1a1b26`)**. Several values are lightened
from Tokyo Night canon to get there: `muted` `#a0a5c0` (canon `#787c99` was
4.18:1), the AAA red `#f88298`, green `#b9f27c`, blue `#7ea5f7`. Same hues,
raised lightness.

**Correction, 2026-09-18.** This rule used to claim `#737aa2` was among the
AAA-calibrated values *and* "the contrast floor for hint/placeholder text". The
build-time gate measured it at **4.10:1** — below AAA, and below AA for normal
text. Both claims could not be true. What is true: it was raised from canon
`#444b6a` (2.5:1, effectively invisible) to 4.10:1, and it is the floor **below
which nothing may go**. It is the `dim` tier — placeholders and terminal bright
black, text that is meant to recede — not an AAA value. The colour was fine; the
documentation was wrong.

This is no longer prose. `home/dani/theme/palette.nix` tiers every role and
`home/dani/theme/default.nix` fails the build if one is out of bounds:

| tier | floor | what it is |
|---|---|---|
| `text` | 7:1 (AAA) | anything read as body text |
| `dim` | 3:1 | deliberately de-emphasised: placeholders, terminal bright black |
| `accent` | warn under 4.5:1 | signal colours and terminal slots — fills, not body text |
| `ui` | none | borders, washes, raised surfaces |

Verified by deliberately breaking it: restoring canon `#787c99` for `muted`
fails with *"only 4.18:1 … WCAG AAA needs 7.0:1"*. Rule 3 is enforced the same
way — a role landing in the cyan band without an explicit `cyanOk` fails, so a
future "just use cyan here" is caught at rebuild rather than by a user who
cannot reliably distinguish it from blue.

### 5. Two type tiers: CaskaydiaMono for chrome, Inter for application UI

**Chrome/shell tier — CaskaydiaMono Nerd Font.** Terminal, waybar, mako,
zathura, imv, SDDM, hyprlock, walker, lazygit all name it. This is what gives
the desktop its voice, and it does not change. Note in-repo: Caskaydia's
capitals have flat-cut apexes by design — they can look "cropped" at list
sizes, which is why walker uses regular (not semibold) weight for list items.

**Application-UI tier — Inter.** Menus, dialogs, portal file choosers and
browser chrome are dense proportional text; a monospace there costs real
readability for no stylistic gain. Added 2026-09-17, replacing an *accidental*
default: before then every unstyled GTK surface rendered in `Ubuntu 10`, a
dconf key left behind by the Cinnamon era that no file in this repo set.

Two traps, both live:

- nixpkgs' `inter` publishes the family name **`Inter Variable`**, not `Inter`.
  Asking for `Inter` falls through to DejaVu Sans silently. Check with
  `fc-match "Inter Variable"`.
- The generic `monospace` alias is now pinned to CaskaydiaMono in
  `fonts.fontconfig.defaultFonts`. Without that, anything requesting plain
  `monospace` got DejaVu Sans Mono and rendered every Nerd Font glyph as tofu.

**Ownership:** `modules/nixos/fonts.nix` installs both families and sets the
fontconfig generic aliases. `home/dani/wm/theme.nix` is the authority for which
font GTK actually uses — via `dconf`, because the xdg-desktop-portal Settings
interface reads dconf and *beats* `gtk-3.0/settings.ini` for every libadwaita
app and every portal dialog.

## Where each surface gets its color

Every surface below now *derives* from the palette — there are no hand-written
colour literals left outside it. Consumers receive it as the `theme` module
argument (plumbed through `specialArgs`/`extraSpecialArgs` in `flake.nix`), which
is also how the system layer reaches it: the SDDM greeter and the Hyprland
desktop read the same roles.

| Surface                     | File                              |
| --------------------------- | --------------------------------- |
| **The palette itself**      | **`theme/palette.nix`** — single source; `home/dani/theme/default.nix` gates it |
| Named-role palette (GTK)    | `wm/theme.nix` → `waybar/palette.css` (generated) |
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
