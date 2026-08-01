# Upstream bug reports

Bugs found in third-party software while building this config, written up
ready to file. Each carries the affected version, the root cause with code
references, a reproduction, and the patch we carry locally.

| Report | Upstream | Local patch | Filed |
| ------ | -------- | ----------- | ----- |
| [walker: grid item layouts never loaded](walker-grid-item-layouts.md) | [abenz1267/walker](https://github.com/abenz1267/walker) | `home/dani/wm/walker-grid-key.patch` | not yet |
| [walker: second theme's picker orphans the first](walker-per-theme-window.md) | [abenz1267/walker](https://github.com/abenz1267/walker) | `home/dani/wm/walker-window-per-theme.patch` | not yet |

## Filing one

`gh` is not installed on this machine, and filing needs your GitHub account
either way. Either paste the report body into the web UI, or:

```fish
nix shell nixpkgs#gh
gh auth login
gh issue create --repo abenz1267/walker \
  --title "<the Title line from the report>" \
  --body-file docs/upstream/walker-grid-item-layouts.md
```

`--body-file` sends the whole file including the metadata header; for a clean
issue, paste only the part below the `---`, or trim it first. When it is
filed, put the issue number in the table above.

## When upstream fixes one

Drop the corresponding patch from the `patches` list in
`home/dani/wm/walker.nix`. They are separate files precisely so either can go
independently. If a walker bump makes a patch stop applying, the build fails
loudly rather than silently reverting the behaviour — that is the intended
failure mode, and it is the signal to check whether the fix landed upstream.
