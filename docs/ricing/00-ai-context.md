# AI Context

## Mission

Evolve this NixOS + Hyprland configuration into an exceptionally polished, modern, animated, keyboard-first desktop while preserving reproducibility, rollbackability, performance, and daily usability.

## Priority order

1. correctness;
2. recoverability;
3. ownership clarity;
4. daily usability;
5. visual coherence;
6. visual ambition.

## Agent rules

- Inspect the repo before editing.
- Use existing project conventions.
- Prefer small reversible changes.
- Never invent file paths when the repository already has a structure.
- Never introduce duplicate ownership.
- Prefer NixOS/Home Manager modules over imperative setup.
- Keep experimental effects gated.
- Keep a shell-independent terminal shortcut.
- Verify upstream docs before generating config for fast-moving tools.
- Treat Hyprland plugins as version-sensitive.
- Test each subsystem before continuing.
- Update docs when architecture changes.

## Ownership model

Exactly one primary owner per responsibility:

| Responsibility | Preferred owner |
|---|---|
| compositor | Hyprland |
| desktop shell | one selected Quickshell shell |
| runtime palette | one selected theme authority |
| wallpaper switching | one backend |
| notifications | shell-native or one daemon |
| clipboard history | shell-native or one backend |
| lock | hyprlock or selected equivalent |
| idle | hypridle |
| GTK/Qt theming | explicitly documented theme owner |
| cursor | Home Manager / Hyprcursor config |
| boot splash | Plymouth |
| greeter | greetd frontend |
| boot manager | systemd-boot unless deliberately changed |

## Failure philosophy

The desktop must remain usable if the shell, wallpaper daemon, palette generator, notification service, visualizer, or an optional Hyprland plugin fails.

Cosmetic failure must never become session failure.
