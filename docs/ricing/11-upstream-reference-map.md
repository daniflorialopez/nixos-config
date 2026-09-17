# Upstream Reference Map

This is a discovery map, not an API guarantee. Fast-moving projects must be checked at the exact repository/flake revision in use before implementation.

## Hyprland ecosystem

- https://wiki.hypr.land/
- https://github.com/hyprwm

Verify current documentation for Hyprland itself and for hyprlock, hypridle, hyprsunset, hyprpolkitagent, hyprpwcenter, hyprshutdown, hyprcursor, hyprlauncher, hyprpaper, hyprpicker, portals, and plugins.

## Shell candidates

### Caelestia
- https://github.com/caelestia-dots/shell

### DankMaterialShell
- https://github.com/AvengeMedia/DankMaterialShell
- https://github.com/AvengeMedia/DankLinux-Docs

### Noctalia
- https://github.com/noctalia-dev/noctalia-shell

### Quickshell
- https://quickshell.org/
- https://github.com/quickshell-mirror/quickshell

## Theming

### Matugen
- https://github.com/InioX/matugen

### Stylix
- https://github.com/nix-community/stylix

## Wallpaper

### swww
- https://github.com/LGFae/swww

## Launcher / command plane

### Vicinae
- https://github.com/vicinaehq/vicinae
- https://vicinae.com/

## Terminal / TUI

### Ghostty
- https://ghostty.org/docs

### Yazi
- https://github.com/sxyazi/yazi
- https://yazi-rs.github.io/

## Notifications

### SwayNotificationCenter
- https://github.com/ErikReider/SwayNotificationCenter

## Screenshots

### Satty
- https://github.com/Satty-org/Satty

## Login

### greetd
- https://github.com/kennylevinsen/greetd

### ReGreet
- https://github.com/rharish101/ReGreet

## NixOS

- https://nixos.org/
- https://wiki.nixos.org/

## Verification procedure for AI agents

Before writing configuration for a fast-moving component:

1. identify the exact nixpkgs/flake pin used by the repo;
2. inspect the current upstream documentation;
3. inspect current NixOS/Home Manager option names;
4. inspect whether a local module already owns the target file;
5. determine failure/rollback behavior;
6. only then generate code.
