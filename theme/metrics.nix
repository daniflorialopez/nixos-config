# theme/metrics.nix — the measurements more than one file has to agree on.
#
# Deliberately four. This is NOT theme/palette.nix for geometry, and that
# difference is the design rather than a shortfall.
#
# The palette earned a full token layer on two counts and geometry has neither.
# It deduplicated ~250 literals across four incompatible syntaxes, and it has an
# objective correctness criterion: home/dani/theme/default.nix measures WCAG
# contrast in Python and fails the build — which already caught
# docs/design-system.md overclaiming about `hint`. No function can say a 14 px
# card radius is wrong. A full radius/gap/border scale here would trade ~120
# commented literals for ~120 uncommented indirections plus a file that reads
# like a design system it cannot enforce. This repo's comments are good:
# hyprland.nix explains its own corner arithmetic in px², walker.nix derives
# 480 = 448 + 2×16 in prose. Replacing prose that says WHY with a name that only
# says WHAT loses information.
#
# The bar for entry is therefore not "is it a geometry value". It is BOTH:
#
#   1. the value is RESTATED somewhere that cannot see its owner — a different
#      file, or a different module system — so no reader ever has both numbers
#      on screen at once; AND
#   2. disagreement is a DEFECT someone would notice, not merely a difference.
#
# Condition 1 is what makes a comment insufficient. Condition 2 is what makes
# the indirection worth paying for. Four values clear both. Everything else
# stays a literal at its call site with a comment saying why it is the number it
# is, which is what the rest of home/dani/wm/ already does well.
#
# Built in flake.nix and handed to BOTH module systems for exactly the reason
# theme/palette.nix and theme/scene.nix are: `cursorSize` has one consumer in
# modules/nixos/ and two in home/, and neither tree may reach into the other.
#
# ---------------------------------------------------------------------------
# WHAT DID NOT CLEAR THE BAR. The omissions are the design, so they are argued
# here rather than left to be rediscovered and "fixed".
#
# decoration.rounding = 16 with rounding_power = 4.0 (wm/hyprland.nix).
#   One owner, one consumer, two adjacent lines. It APPEARED to have a second
#   consumer: waybar carried `border-radius: 12px; /* = decoration.rounding */`.
#   That comment had been false since fc14b5d and no token can make it true,
#   because the two renderers do not draw the same shape from the same number.
#   GTK's border-radius is a circular arc (exponent 2); Hyprland's is a
#   superellipse at exponent 4. Measured as area clipped from the corner's
#   bounding square:
#
#       window r16 p4 ->  18.68 px²      island today r12 p2 ->  30.90 px²
#       island "unified" to r16 p2 ->  54.94 px², i.e. ~3x the window it is
#       supposed to be agreeing with
#
#   (That model reproduces the two figures hyprland.nix computed by hand —
#   "~18.7" and "~30.9" — so it is this repo's own maths.) Numeric equality
#   would make the corners disagree VISUALLY. The claim was deleted (f52a3aa)
#   rather than enforced, and after that there is no second copy of the window
#   rounding anywhere for a token to unify.
#
# gaps_in = 6.
#   A real relationship — half of gaps_out, so 6+6 between two windows equals
#   the 12 that shows to the edge — but it sits on the line directly above its
#   partner. Fails condition 1. A comment is as good as a binding when both
#   numbers are visible together, and a binding is strictly worse here: it hides
#   a number Hyprland's own documentation discusses.
#
# border widths 1 / 2 / 3.
#   Three widths across six roles: window frame, popup frame, notification
#   frame, container hairline, divider rule, and `1px solid transparent` used
#   only to reserve layout so a colour-only selection cannot shift anything by a
#   pixel (walker.nix, three sites). That last is not a visual value at all. A
#   `hairline` token would silently merge a rendering decision with a layout
#   trick; a `frame` token would make a change to window borders restyle
#   notifications. Six roles, three numbers, each contained in one file.
#
# the waybar island -> workspace pill pair.
#   Tempting to derive, and it is NOT concentric — measured rather than assumed.
#   The pill is inset from the island's outer edge by 1 (island border) + 0
#   (island vertical padding) + 4 (pill margin) = 5 px vertically, and by
#   1 + 8 (island horizontal padding) + 2 (pill margin) = 11 px horizontally.
#   Its corners sit nowhere near the island's and no single inset term exists to
#   subtract. The arithmetic that looks like it works (12 - 1 - 4 = 7, round up
#   to 8) does so only by picking the vertical axis and dropping the border;
#   substitute the horizontal inset and it gives 1. A derivation that depends on
#   which of two unequal insets you choose is not a constraint.
#
# the 4 / 8 / 12 / 16 / 24 / 32 spacing scale suggested in
# docs/ricing/02-visual-system.md.
#   Rejected on measurement, not taste. The paddings and margins actually
#   shipped include 2, 5, 6, 9, 10, 14, 18, 20, 26 and 34, and most are
#   load-bearing in a way a scale cannot express: 9 is what fits a single digit
#   at 13 px type, 18 is whatever turns a 64 px icon into a 100 px square tile,
#   34 is the bar height every radius inside it is bounded by. Snapping them is
#   a redesign of the bar and of every walker popup, and this repo's convention
#   is that visual changes ship one at a time with a live A/B.
#
# SDDM ScreenWidth / ScreenHeight, and the monitor modes.
#   modules/nixos/desktop/sddm.nix pins 2560x1440 and is reached by BOTH
#   legionix and danix-hp, while wm/hyprland.nix names HDMI-A-1/eDP-1
#   unconditionally for every host. That is a host-specific hardware fact that
#   is ALREADY shared too widely. Pulling it in here would launder a pre-existing
#   multi-host wart into an endorsed design decision. It needs a per-host NixOS
#   option, not a token — a separate task.

{ lib }:

rec {
  # ------------------------------------------------------------------ the four

  # The desktop's outer margin: how far anything floating sits from the edge of
  # the usable area. Four sites, three files, ONE decision:
  #
  #   wm/hyprland.nix           general.gaps_out      tiled area   -> edge
  #   wm/waybar.nix             margin-left/-right    island       -> edge
  #   wm/hyprland-services.nix  mako margin           notification -> edge
  #
  # waybar's header already claimed this ("side margins 12 (= gaps_out)") and
  # was right; mako's 12 matched by accident and said nothing. Drift is directly
  # visible — a notification and a window edge are on screen together a few
  # hundred pixels apart, and a 2 px disagreement reads as a mistake.
  #
  # NOTE what this is NOT. waybar's margin-top is 8 on purpose ("a touch tighter
  # on top") and stays a literal there. Only the SIDE margins are this value; a
  # token that swallowed the recorded asymmetry would be worse than the literals
  # it replaced.
  outerMargin = 12;

  # The radius of a glass island: waybar's three module groups and the swayosd
  # volume/brightness overlay. Two sites, two files.
  #
  # This is the one DECLARED cross-file copy in the geometry inventory that was
  # never enforced. swayosd.nix says the OSD is "a glass Tokyo Night pill
  # matching the waybar islands (same bg/border/radius)", and two thirds of that
  # sentence are already structural through the palette — both surfaces resolve
  # to `cssRgba "bg" "0.85"` on a `cssRgba "fg" "0.10"` hairline, the identical
  # expressions. Only the radius third was prose, and prose about a radius is
  # precisely what rotted eleven lines away in waybar.nix.
  #
  # The name is the repo's own word ("three floating glass islands") and is
  # chosen to BOUND MEMBERSHIP, because four other 12 px radii sit one grep away
  # and the failure mode of a token layer is a magnet. An island is this specific
  # material: 0.85 bg, a 10 % fg hairline, a floating rounded box. The others are
  # not islands and must not be folded in:
  #   - waybar's tooltip is an OPAQUE @bg box — a different material;
  #   - mako is accent-framed at 2 px and urgency-switched — a framed
  #     notification, not glass;
  #   - walker's .preview is a pane inside a 20 px popup;
  #   - SDDM's RoundCorners is one knob for another renderer's whole surface
  #     family, and cannot participate anyway.
  # They agree today by coincidence.
  #
  # It is NOT decoration.rounding and must never be set from it (see header).
  # It is also bounded from above by waybar's own 34 px bar: at 16 the island has
  # 34 - 32 = 2 px of straight vertical edge left and stops reading as a panel.
  # wm/waybar.nix asserts that bound where both of its terms are visible, rather
  # than dragging the bar height in here.
  islandRadius = 12;

  # Cursor size. Three sites, two module systems, zero enforcement:
  #
  #   wm/cursor.nix                   home.pointerCursor.size
  #   wm/theme.nix                    dconf .../interface cursor-size
  #   modules/nixos/desktop/sddm.nix  settings.Theme.CursorSize
  #
  # The strongest case in the inventory and the only one a comment cannot fix:
  # no comment in home/ is visible from modules/nixos/. It is also the one
  # measurement a user tracks continuously across that boundary — greeter to
  # session to portal dialog — so disagreement shows up as the pointer changing
  # size at login. wm/theme.nix already documents the cursor-THEME half of this
  # coupling deliberately; this makes the size half structural rather than
  # aspirational.
  #
  # Not a gap, radius or border, so strictly outside the tracker row's wording.
  # It is here because it is the clearest instance of the row's actual problem.
  cursorSize = 32;

  # The wallpaper thumbnail contract. wm/wallpaper.nix generates thumbnails at
  # this size; walker.nix's dani-wall item layout hands the identical numbers to
  # a GtkPicture as width/height-request.
  #
  # Both sides already comment it — the only cross-file geometry agreement in the
  # repo documented from both ends — because breaking it is a FUNCTIONAL bug, not
  # a drift: a GtkPicture reports its texture's own width as its natural width
  # and a GridView sizes cells to that, not to the width-request, so a 2x
  # thumbnail silently doubles every cell until the contact sheet is wider than
  # the screen.
  #
  # This is the only geometry value in the repo with an objective correctness
  # criterion, which is exactly what qualified the palette. It is an interface
  # between a generator and a consumer rather than a style choice, so it is named
  # `thumb` and not given a design-ish name.
  #
  # 16:9, generated 1:1. The 1:1 is load-bearing: every px in this repo is a
  # device pixel because wm/hyprland.nix sets scale 1 on both panels.
  thumb = {
    width = 288;
    height = 162;
  };

  # ------------------------------------------------------------------ the view
  # One helper, not eight. The palette needs hex / noHash / ox / hyprRgba /
  # cssRgba / cssRgb / hexA because four consumers spell a colour four
  # incompatible ways. Geometry has one canonical form — an integer count of
  # device pixels — and only CSS needs decoration:
  #
  #   Hyprland, waybar settings, mako, dconf, GtkBuilder XML : the bare integer
  #   waybar style, swayosd style                            : px
  #   SDDM themeConfig (every value there is a QML string)    : toString
  #
  # Deliberately NOT applied to structural zeros: `px 0` is "0px", and the repo
  # writes `padding: 0 8px` and `margin: 0`. Those stay literal (see the refusal
  # list above), so byte-identity holds by policy rather than by hoping the
  # helper is never pointed at a zero.
  px = n: "${toString n}px";
}
