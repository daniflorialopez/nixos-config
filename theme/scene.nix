# The scene: the one image this machine shows when no choice has been recorded.
#
# Built once in flake.nix and handed to BOTH module systems, for exactly the
# reason theme/palette.nix is: modules/nixos must not reach up three directories
# into home/, and home/ must not guess at a value a system module declared.
#
# Before this there were two owners of "what picture represents this machine",
# in two layers, and they did not agree. modules/nixos/desktop/sddm.nix said
# wallhaven-jevzkp.jpg; home/dani/wm/wall-apply.nix's fallback said default.png.
# Nothing reconciled them and nothing detected the disagreement, so the single
# state in which all three surfaces could have agreed for free — no recorded
# selection, or a selection that will not decode — was the one state in which a
# mountain sunset handed off to a bright blue NixOS logo (#1C8ED9 average,
# measured). The failure path broke the scene worse than the success path ever
# did, which is precisely backwards.
#
# Note what this is NOT. It is not the current wallpaper. That lives in
# ~/.local/state/wallpaper/current, is written by wall-set, and is Tier 2 under
# ADR-005 — Nix never declares its value. This is only the anchor the system
# falls back to, which is why one value can legitimately serve the greeter (a
# build-time pin) and the desktop (a runtime fallback) at once.
{
  # A single-file path literal, never "${../home/dani/assets/wallpapers}/x.jpg".
  # The directory form makes every consumer's hash track all sixteen images, so
  # touching any unrelated wallpaper churns the consumer — the churn 8aa1303
  # already had to fix once for wall-apply.
  #
  # 5120x2880, so it is downscaled rather than upscaled onto the two 2560x1440
  # panels. default.png was 1920x1200 and upscaled.
  #
  # Consolidating the two references into this one also discharges half of
  # .gitignore's standing instruction: when assets/wallpapers is finally
  # untracked, only this line needs to move to a fetched derivation, rather than
  # hunting every module that named an image by hand.
  anchor = ../home/dani/assets/wallpapers/wallhaven-jevzkp.jpg;
}
