# Scratchpads & walker theming

`$mod+S` opens a 4×3 board of icons. Pick one and the app appears as a
floating, centred window on a hidden workspace; press `$mod+S` again and it
goes away. Twelve apps, one key, no window management.

This is plain Hyprland — no pyprland. Two files own it:
`home/dani/wm/hyprland.nix` (the mechanism and the menu) and
`home/dani/wm/walker.nix` (how the board looks).

## How a scratchpad works

Each entry lives on its own **special workspace**, a Hyprland workspace that
is hidden until toggled and never appears in the workspace list.

The `scratchpad` helper (`wm/hyprland.nix`) takes a name, a target size as a
percentage of the focused monitor, and the command to run:

```
scratchpad <name> <width%> <height%> <command…>
scratchpad bt 55 60 blueman-manager
```

- **Already spawned** — just `togglespecialworkspace`, i.e. show or hide it.
- **First use** — reveal the workspace, spawn the app into it with
  `[workspace special:<name>]`, then poll `hyprctl clients` (up to 5 s) for the
  window to map and finally float, size and centre it.

**Why geometry is set from the script and not from `windowrulev2`:** static
rules match on `class`, and Chromium sets its Wayland app-id *late*. The rule
would miss and WhatsApp opened at the wrong size. Driving it from the script
after the window has actually mapped is deterministic, and works for any app
without adding a rule per app.

`$mod+S` itself goes through `scratchpad-toggle`, which first asks whether any
special workspace is currently shown:

- **One is showing** → hide it. So `$mod+S` dismisses whatever is up.
- **Nothing showing** → open the picker.

That is why the same key both summons and dismisses.

## The menu

The board is an **elephant `menus` provider**, written to
`~/.config/elephant/menus/scratchpads.toml` from `wm/hyprland.nix`. Each entry
is a label, an icon name, and an `open` action.

| | | | |
| --- | --- | --- | --- |
| Bluetooth | btop | Quick note | WhatsApp |
| Bitwarden | Terminal | Files | Audio |
| Calendar | GPU | Wi-Fi | Weather |

Order matters — walker fills the grid row by row, so the first four are the
most-used and land in the top row. Twelve entries is exactly 4×3, which is
what the window is sized for; a thirteenth starts a fourth row and the board
scrolls.

Two entries need their own wrapper, both generated in `wm/hyprland.nix`:

- **`quick-note`** — `nvim ~/notes/scratch.md`, creating `~/notes` if needed.
  Wrapped so the scratchpad command stays a flat word list with no nested
  quoting through `hyprctl dispatch exec`. Runs with **`-n` (no swap file)
  plus an autosave autocmd** — see [dismissing is not
  closing](#dismissing-is-not-closing) below.
- **`bitwarden-web`** — the Bitwarden web vault as a Chromium PWA in its own
  profile, same pattern as `whatsapp-web`. Chosen over `bitwarden-desktop`,
  which bundles an Electron flagged insecure and would need a system-wide
  `permittedInsecurePackages` override just to build.

`scratchpad` is referenced by **absolute store path** in the TOML, because the
elephant service that runs the action does not inherit the graphical session's
`PATH`. The apps it then spawns via `hyprctl dispatch exec` *do* inherit it, so
those stay bare names.

### Dismissing is not closing

`$mod+S` **hides** a scratchpad; the process keeps running until you quit it or
log out. That is what makes reopening instant, and it is why the hidden window
is still found by `hyprctl clients` (the `scratchpad` helper's "already
spawned?" check), so a second copy is never launched.

The cost is that every scratchpad you have ever opened stays resident for the
session — including `btop`, `nvtop` and the two Chromium PWAs — and that apps
holding state get **killed rather than closed** at logout.

`nvim` is the one that noticed. When it dies from a signal it deliberately
*preserves* its swap file, so a quick-note left hidden through a reboot greeted
the next open with `E325: ATTENTION, found a swap file`. The fix is in the
`quick-note` wrapper: `-n` disables the swap outright, and

```
-c 'autocmd InsertLeave,TextChanged,FocusLost <buffer> silent! update'
```

writes the buffer whenever it changes — `update` is a no-op when unmodified.
`FocusLost` fires the moment `$mod+S` hides the window, so **dismissing the
scratchpad saves the note.** The swap has nothing left to recover that the file
does not already hold. This is scoped to the wrapper; `nvim` everywhere else
keeps its swap files.

Anything else that should not simply be killed at logout wants the same
treatment — autosave, or an entry that closes on dismiss instead of hiding.

### Adding an entry

Add an `[[entries]]` block in `wm/hyprland.nix`, pick a width/height that
suits the app, and make sure the icon name exists in the icon theme. If the
app is not already installed, add it to `home.packages` in the same file.
Keep the total at twelve unless you also change the geometry — see below.

## Why the board has its own walker theme

`$mod+Space` (the launcher) uses `dani-soft`; the board uses `dani-grid`.
They are separate **themes**, not two stylesheets, because in walker a theme
directory owns `layout.xml` — the window geometry — and not just `style.css`.
The shared layout is a fixed 600×570 box, which leaves a 12-icon grid swimming
in dead space. `dani-grid` ships its own layout sized to the board.

The numbers are interlocking, so change them together
(`gridCss` and `gridLayout` in `wm/walker.nix`):

| Where | Value | Why |
| ----- | ----- | --- |
| `columns."menus:scratchpads"` | 4 | applied at runtime; **overrides** the GridView columns in the XML, so the two must agree |
| `Scroll` min/max-content-width | 448 | 4 cells × 112 px |
| `BoxWrapper` width-request | 480 | 448 + the 16 px wrapper padding either side |
| tile margin / padding | 6 / 18 | 112 − 12 margin = 100 px tile; 18 × 2 + 64 icon = 100 |
| `-gtk-icon-size` | 64 px | |
| `Scroll` max-content-height | 400 | 3 rows × 112 = 336, so no scrollbar |

There is deliberately **no `height-request`** — the window is exactly as tall
as the board.

Visually: tiles are bare icons on the window background at 70 % opacity, and
only the selected one gets a card (accent fill + ring) and full opacity. With
twelve panels all competing, nothing read as selected.

### Rules that bite

- **`--theme` must be passed on every walker bind.** All six pass it. Walker
  sets the theme only when the flag is present and never resets it, so an
  unpinned launcher inherits whichever theme ran last.
- **Walker scans themes once, at daemon startup.** A theme edit is invisible
  until the daemon restarts, and an unknown `--theme` silently falls back to
  walker's built-in default — a labelled list. This is why the themes are
  declared via `programs.walker.themes` rather than raw `xdg.configFile`: the
  module folds them into the unit's `X-Restart-Triggers`, so a switch restarts
  walker. Note the trigger hashes config/themes/elephant but **not** the
  package; a patch-only change restarts walker because `ExecStart` moves.
- **`--nosearch` and `--nohints`, not layout properties.** Walker re-shows the
  hint bar whenever the selection changes, and deleting the `GtkEntry` from
  `layout.xml` leaves the board *empty* — the initial query is fired by that
  entry's `changed` signal, so with no entry nothing ever asks elephant for
  the items. Both flags are per-invocation and reset on every launch, so
  neither leaks to the other pickers.
- **XML comments may not contain `--`.** The Nix build will not catch it; the
  theme just fails to parse at runtime.
- **The layout must keep every required object id** even if hidden: `Window`,
  `Scroll`, `List`, `ElephantHint`, `Error`, `BoxWrapper`, `ContentContainer`,
  `Keybinds`, `GlobalKeybinds`, `ItemKeybinds`. The renderer errors without
  them.

## The two walker patches

Both fix real upstream bugs and are written up in
[docs/upstream/](upstream/README.md) ready to file.

- **`walker-grid-key.patch`** — walker never reads `item_<provider>_grid.xml`
  and derives a lookup key nothing matches, so *no one* can theme a grid tile.
  Without it the board renders as a labelled list.
- **`walker-window-per-theme.patch`** — walker builds one window per theme but
  tracks visibility in one global flag and uses a display-global CSS provider,
  so opening one picker over another orphaned the open window and then
  restyled it. Without it, `$mod+S` over `$mod+Space` (or the reverse) leaves
  a stray, mis-rendered window until you press a bind twice.

They are separate files so either can be dropped independently when upstream
fixes it. If a walker bump makes one stop applying, the build fails loudly
rather than silently reverting the behaviour.

## Troubleshooting

| Symptom | Cause |
| ------- | ----- |
| Board is a labelled list | walker daemon predates the theme, or `--theme` names a theme it does not know → it fell back to the built-in default. Switch (restarts walker) and check the theme dir exists under `~/.config/walker/themes/`. |
| `$mod+Space` looks wrong after `$mod+S` | the per-theme window bug — confirm `walker-window-per-theme.patch` is in the `patches` list and that walker actually restarted. |
| Tiles float in too much space | `columns` and the GridView/Scroll widths disagree; recompute the table above. |
| App opens at the wrong size | it is not going through `scratchpad`, or the window took >5 s to map. |
| Quick note opens on a swap-file prompt | an old `nvim` was killed with the swap still live — delete the orphan under `~/.local/state/nvim/swap/`. Should not recur: the wrapper runs `nvim -n`. |
| A scratchpad app is still eating RAM | by design — dismissing hides it. Quit the app itself, or log out. |
| Entry does nothing | icon name typo'd (renders blank) or the command is not on `PATH` for the elephant service — use an absolute store path. |
