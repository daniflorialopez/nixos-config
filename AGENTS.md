# AI Agent Guide — NixOS Configuration Repository

This repository contains a declarative NixOS configuration. Preserve reproducibility, rollbackability, and clear ownership boundaries.

## Ricing project

Before making ricing-related changes, read:

1. `RICE_PLAN.md`
2. `docs/ricing/00-ai-context.md`
3. `docs/ricing/01-current-state.md`
4. `docs/ricing/04-roadmap.md`
5. `docs/ricing/05-nix-architecture.md`
6. `docs/ricing/07-testing-and-rollback.md`

The complete index is `docs/ricing/README.md`.

## Mandatory rules

- Inspect existing configuration before editing.
- Follow the repository's existing module conventions.
- Prefer NixOS/Home Manager configuration over imperative installers.
- Never let two systems own the same generated file.
- Keep experimental visual features optional.
- Keep the session operable if the desktop shell crashes.
- Never make cosmetic components necessary for boot.
- Preserve a direct Hyprland terminal shortcut as a recovery path.
- Pin fast-moving Hyprland/Quickshell/shell dependencies.
- Treat Hyprland plugins as compositor-version-sensitive.
- Verify fast-moving upstream APIs and Nix options before writing configuration.
- Record architecture/ownership changes in `docs/ricing/06-decisions.md`.
- Update `docs/ricing/08-implementation-tracker.md` as work progresses.

## Before every ricing change

Ask:

1. What owns this responsibility now?
2. Which file/module configures it?
3. What should own it afterward?
4. Could Home Manager and runtime generation conflict?
5. What is the fallback if it fails?
6. How is it disabled?
7. How is it rolled back?
8. What persistent CPU/GPU/VRAM cost does it add?

## Source of truth

The repository is authoritative for current implementation state. Documentation expresses goals and decisions.

If `docs/ricing/01-current-state.md` is stale, inspect the repository and update it before making assumptions.
