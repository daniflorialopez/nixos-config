# Component Catalog

## Desktop shell

Evaluate exactly one primary shell:

- Caelestia
- DankMaterialShell
- Noctalia
- custom Quickshell

Evaluate Nix integration, stability, performance, multi-monitor behavior, theming, launcher, notifications, OSD, control center, keyboard accessibility, and maintenance burden.

## Compositor

Keep Hyprland unless a concrete limitation justifies migration.

Explore selectively:

- advanced blur/layer blur;
- glow;
- custom curves;
- motion blur;
- wobble;
- per-app rules;
- special workspaces;
- monitor-aware behavior;
- optional plugins.

## Theme

Candidates:

- shell-native theming;
- Matugen;
- Stylix;
- custom generated templates.

Pick one runtime authority.

## Wallpaper

- swww: preferred candidate for smooth runtime transitions;
- hyprpaper: conservative/reliable option;
- mpvpaper: showcase-only video wallpaper.

## Launcher / command plane

Candidates:

- Vicinae;
- shell-native launcher;
- Hyprlauncher.

Desired responsibilities include apps, files, clipboard, emoji, browser tabs, projects, SSH, wallpaper/theme/profile switching, audio/Bluetooth/Wi-Fi/VPN, screenshots, recording, Nix rebuilds, generation inspection, and power actions.

## Notifications / control center / OSD

Prefer shell-native implementations when strong enough; otherwise use exactly one dedicated daemon.

Control center should expose audio, microphone, devices, Wi-Fi, Bluetooth, brightness, night temperature, VPN, power, DND, media, battery, recording, and effect profile.

OSD should cover volume, mute, brightness, media, caps lock, optional keyboard-layer state, and power profile.

## Hyprland-native services

Evaluate/integrate:

- hyprlock;
- hypridle;
- hyprsunset;
- hyprpolkitagent;
- hyprpwcenter;
- hyprshutdown;
- hyprcursor;
- hyprpicker.

## Clipboard

Use shell-native history or cliphist, never competing managers.

## Terminal / file management

Target candidates:

- Ghostty;
- Yazi;
- fish;
- optional Starship/custom prompt;
- bat;
- fzf;
- btop;
- git TUI.

Keep one graphical file manager for drag-and-drop, removable media, and GUI-only workflows.

## Browser / editors

Theme Firefox chrome deeply but preserve readability.

Theme Neovim, JetBrains, and any other editor with the same semantic palette where practical.

## GTK / Qt / icons / cursor

Unify palette, fonts, icons, cursor, and density.

Prefer broad icon coverage over exotic incompleteness.

Configure both Hyprcursor and XCursor fallback.

## Screenshots / recording

Suggested screenshot stack:

```text
grim + slurp + Satty + clipboard integration
```

Recording should have monitor/region choice, audio-source choice, clear recording indicator, stop action, and predictable output path.

## Workspaces

Possible UI:

- animated pills;
- occupancy;
- app icons;
- live previews;
- monitor-aware state.

Special-workspace candidates: terminal, music, notes, monitoring, communications.

## Overview / plugins

Overview is optional. Plugins must be pinned to Hyprland compatibility, independently disableable, and never required for recovery.

## Window rules

Examples:

- IDE mostly opaque;
- terminal mildly translucent;
- calculator floating;
- PiP always on top;
- games opaque/effects reduced;
- authentication prompts opaque/readable.

## System HUD

Optional on-demand overlay for CPU/GPU, temperatures, RAM/VRAM, disks, network, battery, power profile, display refresh, audio device, active effect profile, and NixOS generation.

## Login / boot

Evaluate greetd + ReGreet or a shell-specific greeter.

Keep Plymouth and align it visually with the greeter.

Keep systemd-boot during the desktop redesign; only later evaluate alternatives such as Limine on a separate branch.

## Performance / reliability

Measure idle CPU, memory, GPU, VRAM, frame timing, animation smoothness, gaming impact.

Every experimental feature needs an enable flag, fallback, rollback path, and documented owner.
