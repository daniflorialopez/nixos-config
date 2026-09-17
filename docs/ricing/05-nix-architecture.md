# Nix Architecture

## One owner per file

For every generated/managed file, identify whether it is owned by NixOS, Home Manager, the shell, Matugen, Stylix, or the application itself. Never allow competing writers.

## Runtime state is acceptable

Legitimate runtime state includes current wallpaper, active effect profile, volume, brightness, connected Bluetooth device, launcher history, and clipboard history.

Nix should declare the mechanism and defaults, not necessarily every transient value.

## Declarative/runtime split

```text
Nix owns:
  packages
  services
  enablement
  paths
  templates
  dependencies
  defaults
  stable design constants

Runtime owns:
  selected wallpaper
  current palette
  temporary effect profile
  transient media state
```

## Feature flags

Gate experimental functionality, for example:

```text
enableExperimentalBlur
enableMotionBlur
enableWobble
enableVideoWallpaper
enableHyprlandPlugins
enableHDR
enableShowcaseMode
```

## Fast-moving inputs

Consider isolating/pinning Hyprland, Quickshell, the selected shell, Hyprland plugins, and theme engine. Align related inputs where upstream compatibility requires it.

## Stable vs bleeding edge

Keep boot/filesystem/networking/security-sensitive base services conservative. Pin fast-moving desktop components separately instead of making the entire OS track arbitrary nightly revisions.

## Recovery paths

Always retain:

- direct Hyprland terminal shortcut;
- shell-independent session control;
- static fallback wallpaper;
- known-good effect profile;
- previous NixOS generations;
- TTY recovery.

## Services and scripts

Use user services where restartability/logs/lifecycle are useful, but do not service-wrap everything.

Custom scripts should use explicit runtime inputs, avoid hidden PATH assumptions, log useful errors, keep state paths documented, and remain small.

## Secrets

Never put API credentials in ricing modules. Weather/calendar/music integrations must use the repo's secret-management approach.

## New-package checklist

1. What responsibility does it own?
2. Is that already owned?
3. Does it need mutable config?
4. Is it available in nixpkgs/as a flake?
5. How often does it break?
6. Does it run persistently?
7. What resources does it consume?
8. How does it fail?
9. How is it disabled?
10. What is the fallback?
