# The palette. One definition, consumed everywhere.
#
# Before this file the colours lived as ~200 literals across ~15 modules in four
# incompatible syntaxes, and `waybar/palette.css` — the thing docs/design-system.md
# called "the canonical named-role definition" — had exactly one consumer. Editing
# a role meant editing every file that had re-typed it, and the names had already
# drifted: palette.css called #565f89 "muted", while design-system.md calls that
# "slate" and gives "muted" to #a0a5c0.
#
# This is Tier 1 of the two-tier model in docs/ricing/06-decisions.md (ADR-005):
# semantic, frozen, Nix-owned, never written at runtime. If a Tier-2 ambient
# generator is ever added it writes to ~/.local/state/theme/ and NEVER here; the
# file boundary is the firewall.
#
# Values are unchanged from what the repo already shipped — this is a refactor,
# not a redesign. Every hex below was lifted from the module that previously
# owned it.
#
# `tier` drives the build-time gate in ./default.nix:
#   text    → must clear WCAG AAA (>= 7:1) against `bg`. Anything read as body.
#   dim     → deliberately de-emphasised text: placeholders, terminal bright
#             black. Floor is 3:1 (WCAG AA for large text / UI components), not
#             7:1. This tier exists because the gate caught design-system.md
#             overclaiming — see the note on `hint` below.
#   ui      → no contrast floor. Borders, washes, raised surfaces.
#   accent  → semantic signal colours and terminal slots; warned under 4.5:1 but
#             not failed, since these are fills rather than body text.
#
# `cyanOk` is the explicit opt-in for the no-cyan rule (design-system.md rule 3).
# Any role whose hue lands in the cyan band without it fails the build — that is
# the point: a future "just use cyan here" is caught at rebuild rather than by a
# user who cannot reliably distinguish it from blue.

{ lib }:

let
  inherit (lib) mapAttrs removePrefix;

  # ---------------------------------------------------------------- the roles

  roles = {
    # --- surfaces -----------------------------------------------------------
    bg        = { hex = "#1a1b26"; tier = "ui"; use = "base background everywhere"; };
    surface   = { hex = "#24283b"; tier = "ui"; use = "raised surfaces: input fields, inactive tabs, meter backgrounds"; };
    selection = { hex = "#283457"; tier = "ui"; use = "selection / hover wash; keeps text readable on top"; };
    overlay   = { hex = "#32344a"; tier = "ui"; use = "terminal 'normal black'; the lightest true surface"; };

    # --- text ---------------------------------------------------------------
    fg     = { hex = "#c0caf5"; tier = "text"; use = "primary foreground"; };
    subtle = { hex = "#a9b1d6"; tier = "text"; use = "secondary text; terminal default foreground"; };
    muted  = { hex = "#a0a5c0"; tier = "text"; use = "dim text. Lightened from canon #787c99, which was ~4.2:1"; };
    # tier = "dim", NOT "text", and the distinction is a correction rather than
    # a convenience. docs/design-system.md rule 4 listed this among the values
    # "lightened ... to WCAG AAA" and called it "the contrast floor for
    # hint/placeholder text". The gate measured it at 4.10:1 on bg — below AAA
    # (7:1) and below even AA for normal text (4.5:1). Both claims could not be
    # true, and the doc has been corrected.
    #
    # What is true: it was raised from canon #444b6a (2.5:1, effectively
    # invisible) to 4.10:1, and it is the floor BELOW WHICH NOTHING MAY GO — not
    # an AAA value. It is only ever used for text that is meant to recede:
    # hyprlock and SDDM placeholders, and the terminal's bright black.
    hint   = { hex = "#737aa2"; tier = "dim"; use = "de-emphasised text: placeholders, terminal bright black. The dim FLOOR — nothing may be dimmer"; };

    # --- lines --------------------------------------------------------------
    slate  = { hex = "#565f89"; tier = "ui"; use = "borders, inactive frames, comments"; };
    gutter = { hex = "#3b4261"; tier = "ui"; use = "inactive window border; dark stop of the active-border value ramp"; };

    # --- semantic -----------------------------------------------------------
    # Rule 1: blue is THE accent. Orange is the attention tier ONLY.
    accent     = { hex = "#7aa2f7"; tier = "accent"; use = "the accent: active frames, highlights, selection"; };
    accentText = { hex = "#7ea5f7"; tier = "text";   use = "AAA-lightened accent, for accent-coloured TEXT"; };
    attention  = { hex = "#ff9e64"; tier = "accent"; use = "ATTENTION TIER ONLY: 'look here' / 'needs you'. Never for merely-active"; };
    warning    = { hex = "#e0af68"; tier = "accent"; use = "warnings; session name; sunset gradient start"; };
    success    = { hex = "#9ece6a"; tier = "accent"; use = "success / valid / healthy"; };
    successText = { hex = "#b9f27c"; tier = "text";  use = "AAA-lightened green, for green TEXT"; };
    critical   = { hex = "#f7768e"; tier = "accent"; use = "errors, alerts; sunset gradient end"; };
    criticalText = { hex = "#f88298"; tier = "text"; use = "AAA-lightened red, for red TEXT"; };
    purple     = { hex = "#bb9af7"; tier = "accent"; use = "vi visual mode, remote-session marker, escapes"; };

    # Rule 3, the accessibility one: no cyan. These two are teal on purpose and
    # are the ONLY roles allowed in the cyan hue band.
    teal    = { hex = "#4fd6be"; tier = "accent"; cyanOk = true; use = "the palette's 'cyan', rendered as teal so it is distinguishable from blue"; };
    tealDim = { hex = "#53c7ad"; tier = "accent"; cyanOk = true; use = "terminal 'normal cyan', same reasoning"; };

    # --- terminal 16-colour extras -----------------------------------------
    # Only needed because a 16-colour palette has slots the semantic roles do
    # not map onto one-to-one.
    magenta     = { hex = "#ad8ee6"; tier = "accent"; use = "terminal normal magenta"; };
    # tier = "accent": this is Tokyo Night's canon bright red and measures
    # 6.88:1 — a hair under AAA. It is deliberately NOT retiered to text and
    # deliberately NOT nudged to clear the threshold: design-system.md's
    # AAA-lightened red is `criticalText` #f88298 (7.03:1), and this is the
    # terminal's 16-colour slot, which should stay canon.
    brightRed   = { hex = "#ff7a93"; tier = "accent"; use = "terminal bright red (canon; the AAA red for text is criticalText)"; };
    brightBlue  = { hex = "#7da6ff"; tier = "text";   use = "terminal bright blue"; };
    white       = { hex = "#a2a5b9"; tier = "text";   use = "terminal normal white"; };
    brightWhite = { hex = "#acb0d0"; tier = "text";   use = "terminal bright white"; };
    searchMatch = { hex = "#3d59a1"; tier = "ui";     use = "fish search-match background; btop net-download gradient start"; };
  };

  # ------------------------------------------------------------------- views
  # Four output syntaxes exist in this repo and all four are load-bearing:
  #   "#rrggbb"   btop, starship, tmux, zellij, GTK CSS
  #   "0xrrggbb"  alacritty, and only alacritty
  #   "rrggbb"    fish's `set -g fish_color_*` — bare, unquoted, no hash. This
  #               is the one a naive `#[0-9a-f]{6}` regex misses entirely.
  #   rgba(...)   Hyprland (packed hex alpha) and GTK (decimal, 0-1 alpha) —
  #               note these two spell rgba() differently, hence two helpers.

  hexDigit = c:
    let t = { "0"=0; "1"=1; "2"=2; "3"=3; "4"=4; "5"=5; "6"=6; "7"=7; "8"=8; "9"=9;
              "a"=10; "b"=11; "c"=12; "d"=13; "e"=14; "f"=15; };
    in t.${lib.toLower c} or (throw "palette: bad hex digit '${c}'");

  # "1a" -> 26
  byteAt = s: i: (hexDigit (builtins.substring i 1 s)) * 16 + hexDigit (builtins.substring (i + 1) 1 s);

  rgbOf = hex: let h = removePrefix "#" hex; in {
    r = byteAt h 0; g = byteAt h 2; b = byteAt h 4;
  };
in
rec {
  inherit roles rgbOf;

  # theme.hex.accent -> "#7aa2f7"
  hex = mapAttrs (_: r: r.hex) roles;

  # theme.noHash.accent -> "7aa2f7"   (fish)
  noHash = mapAttrs (_: r: removePrefix "#" r.hex) roles;

  # theme.ox.accent -> "0x7aa2f7"     (alacritty)
  ox = mapAttrs (_: r: "0x" + removePrefix "#" r.hex) roles;

  # Hyprland: rgba(RRGGBBAA) with a PACKED hex alpha.
  #   theme.hyprRgba "accent" "ff" -> "rgba(7aa2f7ff)"
  hyprRgba = role: alphaHex: "rgba(${noHash.${role}}${alphaHex})";

  # GTK/CSS: rgba(R, G, B, A) with DECIMAL channels and a 0-1 alpha.
  #   theme.cssRgba "bg" "0.85" -> "rgba(26, 27, 38, 0.85)"
  cssRgba = role: alpha:
    let c = rgbOf hex.${role};
    in "rgba(${toString c.r}, ${toString c.g}, ${toString c.b}, ${alpha})";

  # The JSON the build-time gate validates, and the artifact a future Tier-2
  # generator would read. Ordered attrs so the output is reproducible.
  json = builtins.toJSON {
    bgRole = "bg";
    roles = mapAttrs (_: r: {
      inherit (r) hex tier;
      use = r.use or "";
      cyanOk = r.cyanOk or false;
    }) roles;
  };
}
