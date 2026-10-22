# Futuristic rice concepts

> Brainstorm, not a plan. Compiled 2026-09-24/25 across three research passes.
> Grounded against the repo as of `01fda18` (Hyprland 0.55.4, waybar, mako, awww,
> Legion 5 15IAH7H, Corne on Vial/QMK). Open work still lives in
> `docs/ricing/08-implementation-tracker.md`; this file only collects ideas. Several of
> them overlap `docs/ricing/10-ideas-backlog.md` and are merged here, not duplicated.

## Repo facts that shaped this list

- **Borders are neutral slate, not a sunset gradient.** Chosen in a live A/B on
  2026-07-22 because the gradient "read as noise". Warm sunset is reserved for
  attention states. So status is never a border: it is `decoration:glow`, warm, and
  only on escalation. Glow exists on 0.55.4 and is not yet used.
- **Theme roles with contrast checks already exist.** `theme/palette.nix` has
  tiers (text/dim/ui/accent), an AAA gate, and the no-cyan gate. The next step is
  exporting W3C DTCG design tokens (first stable spec 2025.10, OKLCH-capable).
- **ADR-005 already has a place for a time-varying palette:** Tier-2 ambient
  generator writes only to `~/.local/state/theme/`, never to `palette.nix`.
- **The Legion 5 15IAH7H keyboard is 4-zone RGB**, not per-key. Per-key/per-layer
  lighting belongs on the Corne firmware (LED presence unverified).
- **Hyprland 0.55 added Lua config and a Layout API.** HM still generates
  hyprlang. `motion_blur` arrives in 0.56.
- **The portal serves Inter Variable**, so variable-weight typography works for
  shell UI. CaskaydiaMono stays for code.
- **Glass taste is clear, not frosted.** Edge refraction fits; heavy frost does not.

## Part 1: What's in the way

1. **Rices are built for a still image.** Time, motion, and months of use are
   not designed.
2. **A theme is a list of colours, not a system.** Solved inside Nix here, but
   there is still no standard runtime channel that pushes a theme to every app.
   The portal only carries color-scheme, accent and contrast.
3. **The bar is the 1995 taskbar with a new skin.** It is always on and full of
   numbers nobody reads.
4. **The compositor only sees pixels.** It can style frames, never content.
5. **Workspaces are numbered slots.** The desktop has no idea what you're
   working on.
6. **Input is only keyboard and mouse.** Gaze, presence, sound and keyboard
   lighting go unused.
7. **Effects cost the same all the time.** Blur costs the same on battery as
   plugged in.
8. **Declarative config and live tweaking pull against each other.** Nix is
   reproducible but slow to change; live tweaks are fast but get lost.
9. **The culture is copy-pasting dotfiles.** No reusable parts, no tests, no
   history.
10. **Everything is designed for 8-bit sRGB.** The Wayland colour-management/HDR
    protocol is merged and Hyprland supports it. Brightness is unused as a
    design channel.
11. **Apps are sealed boxes.** A rice stops at the window edge (Mercury OS's
    critique).
12. **Accessibility and aesthetics are treated as opposites.** AT-SPI, and
    Newton next, is the only structured view inside apps, and ricers ignore it.
13. **No permission model for a desktop that senses you.** Nothing defines
    "may know X, must never keep or send it".
14. **Notifications are built to grab attention**, as on phones.
15. **One screen, one device.** Phone, e-ink, keyboard and room lights are
    outside the rice.
16. **Nobody measures a rice.** No latency, attention-cost or watts-per-hour
    numbers.
17. **Blur has only just been standardised.** `ext-background-effect-v1` was
    merged in 2026; niri, KDE and GNOME implement it. Until it is universal,
    glass is a compositor-specific hack.
18. **Motion is written as durations and bezier curves**, which cannot be
    redirected mid-animation. Springs can (Material 3 Expressive), but Hyprland's
    animation system has no springs.
19. **XWayland apps are invisible second-class citizens.** Measured at ~3 ms
    extra latency over native Wayland, and nothing on screen says which windows
    are XWayland.
20. **Nobody designs for the user's own eyes.** Palettes follow generic WCAG.
    The cyan problem shows the real criterion is personal colour discrimination.
21. **Generated UI has no design language to follow.** AG-UI, MCP Apps and
    OpenUI exist but ship web components. "The design system is the OS for
    GenUI", and none exists for a desktop.

## Part 2: Ideas

### Horizon 0: buildable now

**Time and state**
- **Palette that follows the sun.** Continuous OKLCH drift through the day, as
  ADR-005's Tier-2 ambient generator, alongside hyprsunset. Workload could shift
  it too.
- **Windows that fade when ignored.** Focus-age drives desaturation and opacity
  (`hyprctl setprop`, or a Lua hook on 0.55+).
- **Motion that means something.** A window opened from a notification enters
  from where the notification was; urgency gets its own curve.
- **Undo for the desktop.** Reopen a closed window with its geometry, and scrub
  through past layouts. Pairs with instant replay (system-improvement #10): a
  gpu-screen-recorder rolling buffer is a visual undo history.
- **Widgets that show how fresh their data is.** A value fades as it ages, so
  stale readings never look current.
- **A picture of your day.** At night, workspace time, commits and focus blocks
  are rendered into tomorrow's wallpaper.

**Kill the bar**
- **Status through glow, not borders.** Borders stay slate; a warm glow is the
  escalation channel.
- **Heads-up display on demand.** Hold a modifier to overlay it on the focused
  window; release for a clean screen.
- **App-aware bar.** Contents depend on the focused app class (IDE, game,
  browser). Already in the backlog.
- **Escalation ladder.** Ambient (tint) → peripheral (glow) → focal (toast) →
  interrupt (sound). Each event has a fixed step and only climbs when it must.
  Mic/camera privacy indicators become steps on it. This is Weiser's calm
  technology turned into rules.

**The theme as a system**
- ~~Theme roles in Nix with contrast checks~~: **done** (`theme/palette.nix`).
  Next: export W3C design tokens so Quickshell, browser userstyles and generated
  UIs read one file.
- **Materials instead of colours.** Glass, paper and metal with physical
  properties, and the cursor as a light source. hyprglass already does
  refraction, rim light and specular highlights; the target here is clear glass
  with refraction only at the edges. `screen_shader` is whole-screen only, so
  per-window effects need a plugin.
- **Type as the main material.** Inter Variable's weight axis in shell UI,
  driven by urgency.
- **Brightness as a design channel.** In HDR, only urgent things may glow
  brighter than normal white, with colours defined in nits. Panel HDR support is
  unverified; 0.55 has per-output ICC and FP16.
- **Spring motion tokens.** A small set of named springs (stiffness and
  damping), split into spatial springs that may overshoot and effect springs
  for colour and opacity that never do (Material 3 Expressive). Real springs in
  QML; bezier approximations for Hyprland.
- **A palette calibrated to your eyes.** A 2-minute hue-discrimination
  reaction test feeds the palette gate, so the no-cyan rule becomes a measurement.

**Beyond the flat rectangle**
- **Keyboard lighting that follows your mode.** The Legion's 4 zones follow
  broad modes via `L5P-Keyboard-RGB` (2022 models supported). The Corne lights
  only the valid keys per layer from its firmware, if it has LEDs.
- **A wallpaper that carries information.** A shader simulation driven by
  typing rate, network or weather. awww makes crossfades cheap.
- **Sound as part of the rice.** A sonify-health-style model: heartbeats,
  thresholds, crossfaded stress layers, via PipeWire.
- **Parallax from head tracking.** Demo tier: cheap, but costs battery and
  privacy.
- **E-ink companion screen.** An old e-reader over VNC for slow-changing
  information. Near-zero power.
- **Mark XWayland windows.** A subtle badge per XWayland window
  (`hyprctl clients` has the flag), justified by the ~3 ms latency figure.

**AI built in**
- **Notification triage by a local model** (fits the 3070's 8 GB), delivered
  as a digest when input goes idle.
- **Window rules in plain language**, turned into a reviewable Nix diff.
- **A rice from one phrase.** A whole mood (motion, sound, density) with
  fixed, reproducible output.
- **A place to watch background agents.** Claude Code hooks (Stop,
  Notification) call a script that drives glow and waybar state.
- **Generated panels in your own design language.** An agent emits a JSON
  panel description and Quickshell renders it with only your components and
  tokens. The agent picks the content; your rules decide the look.

**Tooling behind a rice**
- **Tweak live, then save as a Nix diff.** Quickshell hot-reload, hyprctl REPL
  (0.56), then "keep" emits a diff. This is CLAUDE.md's "test live before
  persisting" as a tool.
- **Screenshot tests for a rice.** A NixOS VM test boots the session and
  compares `grim` screenshots against references in CI.
- **Rice history.** A screenshot per NixOS generation, browsable.
- **Parts with defined inputs.** Flake modules with typed options and preview
  renders.
- **Numbers for a rice.** Frame times during animations, watts per effect, and
  real end-to-end latency from a photodiode clicker (Click2photon approach),
  reported with the existing MangoHud tooling.
- **Effects that scale down automatically.** RICE_PLAN's effect profiles
  (daily, cinematic, gaming, battery, reduced-motion), switched by GameMode,
  battery and temperature.
- **A shelf for things in progress.** Clipboard and dragged items as visible
  objects parked at the screen edge.
- **Custom layouts via the Layout API.** A Lua layout per project type,
  switched by project workspaces.

**Desktop that knows what you're doing (partly doable now)**
- **Workspaces as projects.** Repo, terminal cwds, browser tabs and notes,
  suspended and resumed together.
- **Window lineage.** Every window records what spawned it, drawn as threads in
  the overview.
- **Zoom with meaning.** Semantic zoom over a scrolling canvas; hyprexpo is a
  starting point.
- **Bring back the Unity menu HUD.** One palette searches any app's actions via
  accessibility data.
- **Reading mode for any app.** Extract content through the accessibility tree
  and re-typeset it.

### Horizon 1: 5–10 years (needs a new protocol, sensor or toolkit change)
- **Intent-first shell (Mercury OS).** Verbs and nouns composed across apps;
  Newton and portal actions are the enablers.
- **Gaze sets focus, not the pointer.** Whatever you're not looking at dims.
  Blocked on webcam gaze accuracy.
- **Presence detection.** Blur on look-away or shoulder-surfer.
- **Voice as a modifier.** Hold a key, look at a window and say "that one,
  split right".
- **Restyling inside apps (malleable software).** Needs GTK/Qt-level hooks.
- **One rice across devices.** Phone, watch, e-ink, keyboard and room lights
  share tokens and the escalation ladder.
- **Widgets with permissions.** A widget may read battery, never clipboard.
- **Blur and glass negotiated by apps.** Apps request glass regions via
  `ext-background-effect`; the rice sets material rules.
- **An HDR-native rice.** Brightness replaces hue as the escalation channel.

### Horizon 2: 10–20 years (the rice leaves the flat screen)
- **Spatial desktop.** Stardust XR today, including a normal-screen mode.
- **The room as the display (Dynamicland).** Communal, projected computing.
- **Body signals.** EEG flow detection holds notifications during flow. Local
  only.
- **Generated UI with the rice as the rules.** The ricer's artifact shifts from
  config to design grammar: how things look, move, escalate and feel. This is the
  key idea for where ricing goes over the next 20 years.

## Test for whether an idea is worth building

Keep an idea only if it carries information you'd otherwise look up, lowers the
desktop's attention cost, or still feels good after six months. Anything that
senses the user must be local only, save nothing, and be easy to turn off.
Anything visual must pass the existing rules: quiet with structure, warm colours
only for attention, nothing louder than the text, no cyan, clear glass.

## What can be built today

**This week, on the current stack:**
- glow plus the escalation ladder (mako and waybar)
- Claude Code agent status
- window fading
- XWayland badge
- Legion zones following submaps
- sound layer
- data-freshness fading
- Tier-2 sun-following palette
- DTCG token export from `palette.nix`
- eye-calibration test
- instant replay (#10)

**Today, but each is a project:**
- a Quickshell shell, which unlocks springs, the heads-up display, zoom with
  meaning, generated panels, the shelf, the app-aware bar and tweak-to-diff; this
  is RICE_PLAN's pending shell bake-off
- hyprglass clear-glass edge refraction, behind an off switch
- screenshot tests and per-generation screenshots
- project workspaces and Lua layouts
- e-ink companion
- local-model triage
- photodiode latency meter

**Prototype or demo only:**
- webcam gaze
- head-tracking parallax
- accessibility-based HUD and reading mode (coverage varies by app)
- Stardust XR normal-screen mode
- OpenBCI flow detection

**Not yet:**
- HDR rice (panel unverified)
- restyling inside apps
- intent-first shell
- room as display

## What can be both bleeding-edge and functional: "the calm instrument"

One rule for everything: **it's quiet until something matters, and how loud it
gets depends on how much it matters.**

- **At rest:** clear glass with light edge refraction, slate borders, Inter
  Variable at regular weight, wallpaper visible through everything. No bar
  numbers; the heads-up display appears when you hold a key.
- **While you work:** ignored windows fade, stale data fades, XWayland windows
  carry a faint badge. The desktop shows where your attention actually is.
- **When something happens:** the escalation ladder decides how loud it gets.
  An agent finishing is a faint warm glow and a soft chord. CI failing is a
  stronger glow, a keyboard zone and a toast. Only a real problem makes a sound
  that asks for action.
- **Motion:** shared spring tokens, so interrupted animations turn around
  instead of snapping.
- **Over the day:** the palette drifts with the sun, and the picture of your
  day becomes tomorrow's wallpaper.
- **Behind it:** design tokens generated from `palette.nix`, effect profiles
  switched by GameMode and battery, and every generation screenshotted and
  measured.

**Build order, one revertable commit each:**
1. Glow plus the escalation ladder.
2. Claude Code agent status.
3. Window fading.
4. Legion zones following submaps.
5. Sound layer.
6. Token export.
7. Quickshell bake-off.
8. Springs and the heads-up display.
9. Edge refraction behind an off switch.
10. Screenshot tests.

## Sources

- [Hyprland 0.55: Lua config, Layout API, ICC, FP16 (Phoronix)](https://www.phoronix.com/news/Hyprland-0.55-Wayland-Comp)
- [Hyprland: Lua-ification of configs](https://hypr.land/news/26_lua/)
- [Hyprland 0.56: motion blur, HDR tonemapping, REPL](https://www.linuxcompatible.org/story/hyprland-056-ships-with-expanded-lua-scripting-motion-blur-and-zero-breaking-changes/)
- [Hyprland lands HDR / color management (Phoronix)](https://www.phoronix.com/news/Hyprland-HDR-Color-Management)
- [Wayland colour management protocol merged (GamingOnLinux)](https://www.gamingonlinux.com/2025/02/wayland-colour-management-and-hdr-protocol-finally-merged/)
- [Wayland Explorer: color-management-v1](https://wayland.app/protocols/color-management-v1)
- [Wayland ext-background-effect-v1 merged (Phoronix)](https://www.phoronix.com/news/Wayland-Background-Effect)
- [Niri 26.04 blur support (Phoronix)](https://www.phoronix.com/news/Niri-26.04-Released)
- [hyprglass plugin](https://github.com/hyprnux/hyprglass)
- [Liquid Glass GNOME extension with refraction shaders (OMG! Ubuntu)](https://www.omgubuntu.co.uk/2026/09/liquid-glass-gnome-shell)
- [Design Tokens spec first stable version (W3C DTCG)](https://www.w3.org/community/design-tokens/2025/10/28/design-tokens-specification-reaches-first-stable-version/)
- [Material 3 motion / springs](https://m3.material.io/styles/motion/overview/how-it-works)
- [State of Generative UI 2026 (OpenUI)](https://www.openui.com/blog/state-of-generative-ui-report)
- [Measuring input latency on Linux: X11 vs Wayland](https://marco-nett.de/blog/measuring-input-latency-on-linux-x11-vs-wayland-vrr-dxvk/)
- [Building an input latency meter](https://davidjusto.com/articles/m2p-latency/)
- [L5P-Keyboard-RGB](https://github.com/4JX/L5P-Keyboard-RGB)
- [sonify-health](https://github.com/LoganBarnett/sonify-health)
- [Quickshell](https://quickshell.org/)
- [Stardust XR](https://github.com/StardustXR)
- [Introducing Mercury OS (Jason Yuan)](https://uxdesign.cc/introducing-mercury-os-f4de45a04289?gi=f83d00b76512)
- [Ink & Switch: Malleable software](https://www.inkandswitch.com/essay/malleable-software/)
- [LWN: Modernizing accessibility for desktop Linux](https://lwn.net/Articles/971541/)
- [GNOME a11y: Update on Newton](https://blogs.gnome.org/a11y/2024/06/18/update-on-newton-the-wayland-native-accessibility-project/)
- [Ambient Analytics: Calm Technology (arXiv)](https://arxiv.org/html/2602.19809)
- [IxDF: Calm Computing](https://ixdf.org/literature/topics/calm-computing)
- [Zylos: Ambient agent presence](https://zylos.ai/research/2026-07-16-ambient-agent-presence-desktop-companions-observability/)
- [GazeTracking](https://github.com/antoinelame/GazeTracking)
- [Using an e-ink tablet as a Linux monitor](https://alavi.me/blog/e-ink-tablet-as-monitor-linux/)
- [Flow detection from portable EEG headbands (arXiv)](https://arxiv.org/pdf/2609.19737)
- [Dynamicland](https://dynamicland.org/)
