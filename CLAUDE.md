# nixos-config

Project notes for Claude Code.

<!-- efootball-perf:begin -->
## This machine

- Host `legionix`: Lenovo Legion, i7-12700H + RTX 3070 Laptop, NVIDIA proprietary driver.
- User `dani`. Flake is this repo. Rebuild: `sudo nixos-rebuild switch --flake .#legionix` (or `nh os switch .`).
- Multi-host flake — changes must not break the non-NVIDIA host or the VM. Guard NVIDIA-specific
  options rather than adding them globally.
- Desktop: Hyprland + waybar + mako + fish. Tokyo Night via `palette.css`.

## Shell rules (important)

The interactive shell is **fish**, not bash.

- Fish has **no heredocs**. Never hand the user `cmd <<'EOF'`. Use `printf`/`echo … | cmd`,
  a `writeText` derivation, or a real file.
- `export VAR=x` is wrong. Fish uses `set -x VAR x`.
- `$(...)` works in fish, but `VAR=x cmd` prefix assignment does not — use `env VAR=x cmd`.
- Brace-containing arguments (e.g. nftables sets like `{ 5736, 30000-35000 }`) must be quoted,
  or fish expands them first.
- Anything genuinely bash-only should be written to a `.sh` file and run as `bash file.sh`.

## Working agreements

- **Never run `sudo` yourself.** Print the exact command and let the user run it. That includes
  `nixos-rebuild`, `tee` into `/sys`, and anything touching `/etc`.
- **Never rebuild without being asked.** Edit, explain, then stop.
- Prefer a **unified diff the user can review** over silently rewriting whole files.
- Use `rg` to search this repo, not `find | grep`.
- Test live before persisting where possible: `hyprctl keyword …` before editing the Nix file.
- One change per commit. Conventional style: `feat(scope): subject`, blank line, body explaining
  why. The user reverts individual tasks, so commits must be independently revertable.
- If a fact is checkable, check it. Do not assume the contents of a file in this repo.

## eFootball performance work

Active project. Read these before acting on it:

- `docs/efootball/PROGRESS.md` — current state, read first, update last
- `docs/efootball/efootball-execution-runbook.md` — the four tasks, step by step, with expected
  output and failure branches for each
- `docs/efootball/efootball-verify.sh` — run during a live match to check all four at once
- `docs/efootball/frametime-report.py` — parses MangoHud CSVs from `~/mangologs`

The four tasks are: (1) refresh rates 60 → 75/165, (2) make GameMode actually engage by putting
`libgamemode.so` inside Steam's FHS via `programs.steam.extraPackages`, (3) remove `PROTON_LOG=1`
from the Steam launch options, (4) platform profile → performance via a GameMode hook.

Steps that happen in Steam's UI or in the game's own settings menu **cannot be done from here**.
Hand those to the user explicitly, wait for confirmation, then continue.
<!-- efootball-perf:end -->
