# The gate that turns docs/design-system.md from prose into a build failure.
#
# This is the actual argument for hand-maintaining a palette instead of adopting
# Stylix or Matugen (docs/ricing/06-decisions.md, ADR-005): neither of them can
# enforce a rule. They generate colours. This checks them.
#
# Two rules are checked, and both are accessibility rules rather than taste:
#
#   1. Contrast. Roles tiered `text` must clear WCAG AAA (7:1) against `bg`;
#      roles tiered `dim` must clear 3:1. These are not decorative thresholds —
#      several values are deliberately lightened from Tokyo Night canon to reach
#      them (`muted` #a0a5c0 from #787c99 at 4.2:1; `hint` #737aa2 from #444b6a
#      at 2.5:1). Without a check, the next person to "restore the canon values"
#      silently undoes that.
#
#      This already earned its keep: on first run it caught design-system.md
#      claiming #737aa2 was AAA-calibrated and "the contrast floor". It measures
#      4.10:1 — below AAA and below AA for normal text. The doc was wrong, the
#      colour was fine, and the `dim` tier now models what it actually is.
#
#   2. No cyan. The user cannot reliably distinguish cyan from blue/white, so a
#      role landing in the cyan hue band is a real usability regression, not a
#      style opinion. Two roles are deliberately teal and carry `cyanOk = true`;
#      anything else in the band fails.
#
# Why a derivation and not `assertions`: the maths needs pow() for sRGB gamma
# expansion, and Nix has no pow, exp or ln. Approximating it would defeat the
# point of a contrast *guarantee*. A tiny Python script gets it exactly right,
# fails the build loudly, and — because the validated JSON is what lands in
# ~/.config/theme/palette.json — the check cannot be skipped: the file every
# consumer can read is the build product of having passed.
#
# No IFD: nothing reads this derivation's output at eval time.

{ pkgs, lib, ... }:

let
  theme = import ./palette.nix { inherit lib; };

  checker = pkgs.writeText "palette-check.py" ''
    import json, sys, colorsys

    data = json.load(open(sys.argv[1]))
    roles = data["roles"]
    bg_hex = roles[data["bgRole"]]["hex"]

    def rgb(h):
        h = h.lstrip("#")
        return tuple(int(h[i:i+2], 16) / 255.0 for i in (0, 2, 4))

    def luminance(h):
        # WCAG 2.x relative luminance: sRGB -> linear, then Rec.709 weights.
        def lin(c):
            return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
        r, g, b = (lin(c) for c in rgb(h))
        return 0.2126 * r + 0.7152 * g + 0.0722 * b

    def contrast(a, b):
        la, lb = luminance(a), luminance(b)
        hi, lo = max(la, lb), min(la, lb)
        return (hi + 0.05) / (lo + 0.05)

    def hue_deg(h):
        r, g, b = rgb(h)
        return colorsys.rgb_to_hls(r, g, b)[0] * 360.0

    AAA = 7.0
    DIM = 3.0   # WCAG AA for large text / UI components
    # Cyan band. Deliberately narrower than "anything greenish-blue": teal at
    # ~168 deg is fine and is what the palette uses on purpose. True cyan sits
    # around 180 and is what has to be caught.
    CYAN_LO, CYAN_HI = 172.0, 200.0

    errors, warnings, rows = [], [], []

    for name, r in sorted(roles.items()):
        h, tier = r["hex"], r["tier"]
        if len(h) != 7 or not h.startswith("#"):
            errors.append(f"{name}: malformed hex {h!r}")
            continue
        try:
            ratio, hue = contrast(h, bg_hex), hue_deg(h)
        except ValueError:
            errors.append(f"{name}: unparseable hex {h!r}")
            continue

        if tier == "text" and ratio < AAA:
            errors.append(
                f"{name} ({h}) is tier=text but only {ratio:.2f}:1 on {bg_hex} "
                f"— WCAG AAA needs {AAA}:1. Lighten it, or retier it: 'dim' if it "
                f"is meant to recede, 'accent' if it is a fill rather than body text."
            )
        if tier == "dim" and ratio < DIM:
            errors.append(
                f"{name} ({h}) is tier=dim but only {ratio:.2f}:1 on {bg_hex} "
                f"— the dim floor is {DIM}:1 and this is the value nothing may go below."
            )
        if tier == "accent" and ratio < 4.5:
            warnings.append(f"{name} ({h}) is {ratio:.2f}:1 — fine as a fill, do not use it for text")

        if CYAN_LO <= hue < CYAN_HI and not r.get("cyanOk"):
            errors.append(
                f"{name} ({h}) has hue {hue:.0f}deg, inside the cyan band "
                f"[{CYAN_LO:.0f},{CYAN_HI:.0f}). See rule 3 in docs/design-system.md: "
                f"cyan is not reliably distinguishable from blue here. Use teal, "
                f"or set cyanOk = true with a reason if it is genuinely teal."
            )
        rows.append(f"  {name:<13} {h}  {ratio:>6.2f}:1  hue {hue:>5.1f}  {tier}")

    print(f"palette: {len(roles)} roles, contrast measured against {bg_hex}")
    print("\n".join(rows))
    for w in warnings:
        print(f"  note: {w}")
    if errors:
        print("\nPALETTE CHECK FAILED:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        sys.exit(1)
    print(f"\npalette: OK — text roles clear {AAA}:1, dim roles clear {DIM}:1, no unflagged cyan")
  '';

  # The validated palette. Emitting the JSON is conditional on passing, so the
  # artifact and the proof are the same object.
  validated = pkgs.runCommand "palette.json" {
    nativeBuildInputs = [ pkgs.python3 ];
    passAsFile = [ "palette" ];
    palette = theme.json;
  } ''
    python3 ${checker} "$palettePath"
    cp "$palettePath" "$out"
  '';
in
{
  # Landing it in the closure is what makes the gate unskippable — `check-all`
  # builds the toplevel, the toplevel needs this file, and this file only exists
  # if the checks passed.
  #
  # It is also the seam a Tier-2 ambient generator would read, without ever
  # being allowed to write here.
  xdg.configFile."theme/palette.json".source = validated;
}
