# Visual System

The desktop should be designed as one visual system, not application by application.

## Geometry

Centralize:

- primary/small radii;
- border thickness;
- window gaps;
- panel/popup padding;
- shadow geometry;
- spacing scale.

Suggested spacing scale:

```text
4 / 8 / 12 / 16 / 24 / 32
```

## Typography

Choose:

- one UI sans-serif;
- one monospace;
- optionally one display face.

Define roles such as display, heading, body, small, caption, monospace.

## Semantic colors

Use shared roles rather than unrelated per-app colors:

```text
background
surface
surfaceRaised
surfaceGlass
foreground
foregroundMuted
accent
accentAlt
success
warning
error
border
shadow
```

## Opacity and blur

Use transparency selectively. Content surfaces should remain readable; transient shell surfaces can be more glass-like.

Use blur primarily for launcher, control center, overview, notifications, floating scratchpads, and lock screen.

## Animation language

Define fast/normal/cinematic durations and a small set of easing curves. Workspace transitions, popups, and window openings should feel related but not identical.

## Profiles

### Daily
Responsive, restrained, readable.

### Cinematic
Richer motion, blur, and glow.

### Showcase
Maximum optional visual features, potentially including animated/video wallpaper.

### Gaming
Disable expensive/disruptive effects and nonessential notifications.

### Battery
Static wallpaper, reduced polling and effects.

### Reduced motion
Near-instant transitions; no wobble/motion blur/parallax.

## Wallpaper-driven palette

Ideal flow:

```text
select wallpaper
-> transition wallpaper
-> generate palette
-> update shell
-> update Hyprland
-> update terminal
-> update GTK/Qt
-> update browser/editor where appropriate
-> refresh lock styling
```

Exactly one component should own runtime palette generation.
