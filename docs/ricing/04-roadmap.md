# Implementation Roadmap

## Phase 0 — Inventory

Fill `01-current-state.md`. Make no broad cosmetic changes yet.

## Phase 1 — Module boundaries

Normalize/document desktop modules. A possible target is:

```text
modules/desktop/
  hyprland/
  shell/
  theme/
  wallpaper/
  lock/
  idle/
  launcher/
  notifications/
  terminal/
  screenshots/
  greeter/
  boot/
```

Adapt to the repo's conventions rather than forcing this tree.

## Phase 2 — Shell bake-off

Test Caelestia, DMS, Noctalia, and custom Quickshell only as necessary. Choose one and remove the others.

## Phase 3 — Design tokens

Centralize fonts, spacing, radii, borders, opacity, shadows, animation timing, semantic colors.

## Phase 4 — Theme authority

Choose shell-native theming, Matugen, Stylix-centric design, or custom generation. Resolve ownership first.

## Phase 5 — Wallpaper system

Evaluate swww; implement transitions, per-monitor behavior, state persistence, fallback, and theme trigger.

## Phase 6 — Hyprland baseline polish

Refine gaps, borders, shadows, rounding, opacity, blur, layer blur, and animation curves. Do not begin with experimental effects.

## Phase 7 — Shell surfaces

Polish bar, launcher, notifications, control center, OSD, clipboard, media, power menu, HUD.

## Phase 8 — Native services

Integrate hyprlock, hypridle, hyprsunset, hyprpolkitagent, hyprshutdown, Hyprcursor, and hyprpwcenter as needed.

## Phase 9 — Application coherence

Theme Ghostty, Yazi, Firefox, Neovim, JetBrains, GTK, Qt, icons, cursor, and terminal utilities.

## Phase 10 — Keyboard command plane

Expose the major desktop actions through keyboard / launcher.

## Phase 11 — Login / boot continuity

Polish greetd/greeter and Plymouth. Do not change boot manager yet.

## Phase 12 — Workspace UX

Add special workspaces, overview, previews, gestures, and app-aware rules selectively.

## Phase 13 — Experimental effects

Gate advanced blur, glow, motion blur, wobble, decorative plugins, and trails behind options/profiles.

## Phase 14 — Operational profiles

Create `daily`, `cinematic`, `showcase`, `gaming`, `battery`, and `reduced-motion`.

## Phase 15 — Audit

Test shell restart, wallpaper/theme failure, monitor hotplug, suspend/resume, gaming, idle resource use, plugin mismatch.

## Phase 16 — Optional bootloader experiment

Only after the desktop is mature, on a separate branch with explicit recovery steps.
