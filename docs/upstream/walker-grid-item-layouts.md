# Upstream report — walker: custom grid item layouts are never loaded

- **Repo:** <https://github.com/abenz1267/walker>
- **Affects:** v2.16.2, rev `aa1e4b7d59237e8c43dde58636bae476f23d9bfb`
- **Our patch:** `home/dani/wm/walker-grid-key.patch`
- **Related:** closes the gap left by #656 (same code path, list items only)
- **Status:** not yet filed

---

## Title

`item_<provider>_grid.xml` layouts are never loaded (grid follow-up to #656)

## Body

### What happens

A theme cannot override the item layout for a provider rendered as a grid.
Dropping `item_menus-scratchpads_grid.xml` into a theme directory has no
effect at all — walker silently keeps its built-in icon+text tile. There is no
warning and no error; the file is simply never read.

#656 fixed exactly this for **list** items (`item_<provider>.xml`, with `:`
written as `-`). The grid variant looks like it was meant to work the same way
— `Theme::grid_items` exists and `src/theme/mod.rs` has a dedicated match arm
for `_grid.xml` — but two separate defects mean it cannot.

### Cause 1 — the file is never in the candidate list

`src/theme/mod.rs` builds the list of filenames it will look for in a theme
directory. The per-provider entries are generated as:

```rust
let additional = PROVIDERS.get().unwrap().iter().map(|v| {
    let p = if v.0.contains("menus:") {
        v.0.replace("menus:", "menus-")
    } else {
        v.0.to_string()
    };

    format!("item_{}.xml", p)     // <-- only the non-grid name
});
```

`item_<p>_grid.xml` is never generated, so no file with that name is ever
iterated, and the `_grid.xml` match arm below is unreachable.

### Cause 2 — the derived key keeps the `_grid` suffix

Even when reached, the grid arm strips the wrong suffix:

```rust
name if name.ends_with("_grid.xml") && name.starts_with("item_") => {
    let key = name
        .strip_prefix("item_")
        .unwrap()
        .strip_suffix(".xml")      // <-- leaves "menus-scratchpads_grid"
        .unwrap();
    ...
    theme.grid_items.insert(actual_key, s);
}
```

That inserts under `menus:scratchpads_grid`, but `src/renderers/mod.rs` looks
the layout up by the bare provider name:

```rust
theme.grid_items.get(&item.provider)
```

so the entry can never match. Fixing either cause alone is a no-op — both are
needed.

### Reproduce

1. Give a provider more than one column, so it renders as a grid:

   ```toml
   [columns]
   "menus:scratchpads" = 4
   ```

2. Put a minimal `item_menus-scratchpads_grid.xml` in your theme directory —
   e.g. an `ItemBox` containing only an `ItemImage`, no `ItemText`.
3. Open that provider.

**Expected:** icon-only tiles.
**Actual:** walker's built-in icon+text tile, unchanged. Nothing is logged.

### Patch

```diff
-        let additional = PROVIDERS.get().unwrap().iter().map(|v| {
+        let additional = PROVIDERS.get().unwrap().iter().flat_map(|v| {
             let p = if v.0.contains("menus:") {
                 v.0.replace("menus:", "menus-")
             } else {
                 v.0.to_string()
             };
 
-            format!("item_{}.xml", p)
+            [format!("item_{}.xml", p), format!("item_{}_grid.xml", p)]
         });
```

```diff
                     let key = name
                         .strip_prefix("item_")
                         .unwrap()
-                        .strip_suffix(".xml")
+                        .strip_suffix("_grid.xml")
                         .unwrap();
```

The non-grid match arm already guards itself with `&& !name.ends_with("grid.xml")`,
so adding the grid filename to the candidate list does not disturb it.

Happy to open this as a PR if that is easier.
