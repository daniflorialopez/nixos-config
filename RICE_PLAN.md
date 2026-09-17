# NixOS Ricing Master Plan

> Status: design blueprint  
> Target platform: NixOS + flakes + Home Manager + Hyprland  
> Goal: build an extremely polished, modern, keyboard-first desktop while preserving reliability, rollbackability, and declarative configuration.

## 1. North-star objective

The system should feel like a deliberately designed operating environment rather than a collection of unrelated dotfiles.

The desired result is:

- visually coherent across boot, login, desktop, lock screen, terminal, browser, editor, and utilities;
- dynamic, animated, and modern without sacrificing usability;
- keyboard-first and compatible with a heavily customized Corne workflow;
- modular and declarative under Nix;
- easy to disable, roll back, or benchmark;
- capable of having both a restrained daily-driver profile and an extravagant showcase profile;
- resilient when optional visual components fail.

The key design principle is:

> **One visual language, one theme authority, one shell architecture, many optional effects.**

## 2. Current baseline assumptions

This blueprint assumes the repository already contains or is moving toward:

- NixOS with flakes;
- Home Manager;
- Hyprland on Wayland;
- systemd-boot;
- Plymouth / quiet boot;
- a wallpaper pipeline based around Hyprpaper and/or Waytrogen;
- a keyboard-heavy workflow;
- a preference for reliability over cosmetic fragility.

Treat these as assumptions to verify in the repository before editing.

## 3. Highest-impact architectural decisions

Before implementing dozens of individual tweaks, decide these five items:

1. **Desktop shell**
   - Caelestia
   - DankMaterialShell
   - Noctalia
   - custom Quickshell shell

2. **Theme authority**
   - shell-native theme engine
   - Matugen
   - Stylix
   - custom generated palette system

3. **Wallpaper authority**
   - swww for animated transitions
   - Hyprpaper for conservative reliability
   - mpvpaper only as an optional showcase mode

4. **Launcher / command palette**
   - Vicinae
   - shell-native launcher
   - Hyprlauncher
   - fallback launcher retained for recovery

5. **Effect policy**
   - daily-driver
   - cinematic
   - showcase
   - gaming
   - battery
   - reduced-motion

These decisions affect almost every later module.

## 4. Recommended target stack

A strong target architecture is:

```text
Firmware
  -> systemd-boot
  -> Plymouth
  -> greetd + graphical greeter
  -> Hyprland
      -> Quickshell-based desktop shell
      -> theme generator
      -> wallpaper engine
      -> launcher / command palette
      -> notifications / control center / OSD
      -> Hyprland ecosystem services
      -> terminal + TUI tools
      -> themed GUI applications
```

Suggested tools to evaluate:

```text
Compositor          Hyprland
Shell               Caelestia / DMS / Noctalia / custom Quickshell
Wallpaper           swww
Theme generation    Matugen or shell-native dynamic theming
Launcher            Vicinae + shell-native fallback
Lock                 hyprlock
Idle                 hypridle
Night temperature    hyprsunset
Polkit               hyprpolkitagent
Audio graph           hyprpwcenter
Shutdown              hyprshutdown
Notifications         shell-native, otherwise SwayNotificationCenter
Clipboard             cliphist or shell-native clipboard history
Terminal              Ghostty
TUI file manager      Yazi
Screenshots           grim + slurp + Satty
Login                 greetd + ReGreet or shell-native greeter
Boot splash           Plymouth
Boot manager          systemd-boot unless a future migration is justified
```

## 5. What not to do

Avoid:

- installing several desktop shells simultaneously;
- allowing Stylix, Matugen, shell-native theming, and handwritten CSS to overwrite the same files;
- making the shell a hard dependency for emergency navigation;
- introducing compositor plugins without a way to disable them;
- replacing systemd-boot solely for aesthetics before the rest of the desktop is finished;
- permanently enabling expensive video wallpapers and experimental compositor effects;
- mixing mutable shell-generated configuration with Home Manager ownership without an explicit boundary;
- using random `curl | sh` installers when the component can be packaged or configured declaratively.

## 6. Implementation sequence

Follow this order:

1. establish architecture and module boundaries;
2. select desktop shell;
3. select theme authority;
4. select wallpaper engine;
5. establish fonts, icons, cursors, geometry, spacing, opacity, and animation language;
6. integrate launcher, notifications, control center, OSD, clipboard, media, and system HUD;
7. migrate lock / idle / sunset / polkit / shutdown to a coherent Hyprland-native stack;
8. theme terminal, browser, editor, GTK, Qt, and common tools;
9. improve login and boot continuity;
10. add special workspaces, gestures, overview, advanced window rules, and optional plugins;
11. add effect profiles;
12. benchmark and optimize;
13. add showcase-only features;
14. document failure recovery and rollback.

## 7. Definition of success

The rice is complete when:

- changing wallpaper can update the system palette coherently;
- the shell, launcher, notifications, lock screen, browser, terminal, and editor visibly belong to the same visual system;
- visual effects can be changed by profile;
- gaming can disable unnecessary compositor cost;
- keyboard-only operation covers almost all desktop actions;
- optional visual features can fail without making the desktop unusable;
- every important component is declared or pinned in Nix;
- a broken experiment can be reverted through Git and/or NixOS generation rollback;
- the system still feels fast at the monitor's native refresh rate.
