# Upstream report — walker: opening a second theme's picker orphans the first

- **Repo:** <https://github.com/abenz1267/walker>
- **Affects:** v2.16.2, rev `aa1e4b7d59237e8c43dde58636bae476f23d9bfb`
- **Our patch:** `home/dani/wm/walker-window-per-theme.patch`
- **Status:** not yet filed

---

## Title

Launching a picker with a different `--theme` while one is open leaves a
stray, restyled window on screen

## Body

### What happens

With walker running as a service and two binds that use different themes:

```
walker --theme theme-a
walker -m some:provider --theme theme-b
```

pressing the second bind while the first picker is open leaves **theme-a's
window still on screen**, and it then gets repainted with theme-b's
stylesheet — so it renders with a layout its CSS does not describe (in our
case an icon grid whose tiles collapsed into a thin strip). Pressing either
bind a second time clears it.

### Cause

Three pieces of state disagree about how many windows exist:

- `setup_window` builds **one `GtkWindow` per theme**
  (`WINDOWS: HashMap<String, WindowData>`, `src/ui/window.rs`).
- `with_window` resolves that map using **`get_theme()`** — the theme of the
  invocation currently being processed.
- `is_visible` is a **single global flag**, and the GTK CSS provider is
  registered once for the whole display
  (`style_context_add_provider_for_display`, `src/theme/mod.rs`), so loading a
  theme's CSS restyles *every* walker window at once.

`handle_command_line` calls `set_theme` for the incoming `--theme` before
`app.activate()` runs. By the time `activate` reaches its close-when-open
branch:

```rust
if (... cfg.close_when_open && is_visible() ...) || is_param_close() {
    if is_visible() {
        quit(app, false);
    }
    return;
}
```

`get_theme()` is already the **new** theme, so `quit()` → `with_window` hides
the incoming theme's window — one that was never visible — while the window
actually on screen is left alone. `quit()` then sets `is_visible = false` and
returns without calling `setup_css`.

The next invocation finds `is_visible == false`, proceeds, and `setup_css`
swaps the display-global provider. The orphan is still mapped, so it is
repainted with the other theme's CSS.

### Reproduce

1. Define two themes, `theme-a` and `theme-b`, with visibly different styles
   (a grid layout for one makes it obvious).
2. Run walker as a service, `close_when_open = true`.
3. `walker --theme theme-a`, then without closing it, `walker --theme theme-b`.

**Expected:** theme-a's picker closes, theme-b's opens.
**Actual:** theme-a's window stays on screen; a second invocation restyles it
with theme-b's CSS.

### Patch

Close the window that is *actually* visible, under its own theme so the
existing teardown runs against the right `WindowData`. This has to happen at
the **top of `handle_command_line`**, before the incoming invocation's options
are stored — `quit()` clears `provider`, `no_search`, `no_hints` and the
geometry overrides, so running it later wipes the state of the picker being
opened rather than the one being closed.

```rust
// src/ui/window.rs
pub fn visible_theme() -> Option<String> {
    WINDOWS.with(|windows| {
        windows
            .get()
            .unwrap()
            .iter()
            .find(|(_, w)| w.window.is_visible())
            .map(|(k, _)| k.clone())
    })
}
```

```rust
// src/main.rs, first thing in handle_command_line
if let Some(visible) = visible_theme() {
    let requested = options
        .lookup_value("theme", Some(VariantTy::STRING))
        .and_then(|v| v.str().map(str::to_string))
        .filter(|t| has_theme(t))
        .unwrap_or_else(get_theme);

    if visible != requested {
        set_theme(visible);
        quit(app, false);
    }
}
```

When the requested theme matches the visible one the block is skipped, so the
normal close-when-open toggle is untouched. Side effect worth having:
switching between two pickers now takes one keypress instead of two.

Happy to open this as a PR if that is easier.
