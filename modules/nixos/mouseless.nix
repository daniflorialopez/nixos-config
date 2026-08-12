{ ... }:

# Mouseless (mouseless.click, by Sonuscape LLC) is proprietary, and on Linux it
# ships only as a Flatpak from the vendor's own GPG-signed repo. There is no
# source to build and nothing to package, so this module just prepares the
# system — the app itself is installed imperatively:
#
#   flatpak remote-add --user --if-not-exists sonuscape \
#     https://dl.sonuscape.net/flatpak/sonuscape.flatpakrepo
#   flatpak install net.sonuscape.mouseless
#
# Do not reach for `pkgs.mouseless`. That is an unrelated MIT-licensed Go tool
# (github.com/jbensmann/mouseless) that happens to share the name.
{
  # Flatpak and its remotes; asserts on xdg.portal.enable, which
  # desktop/hyprland.nix already sets.
  imports = [ ./flatpak.nix ];

  # Wayland will not hand an application global hotkeys or synthetic pointer
  # events, so Mouseless goes under the compositor: it takes an exclusive evdev
  # grab on the keyboards (/dev/input/event*, group `input`) and replays the
  # keystrokes it is not swallowing through a virtual device it creates via
  # /dev/uinput (group `uinput`).
  #
  # The cost, stated plainly: membership in `input` lets *any* process running
  # as dani read every keystroke on this machine, passwords included. That is
  # X11's threat model, and the vendor documents no smaller grant that works.
  #
  # uinput is already on transitively (keyd.nix -> hardware.uinput.enable), but
  # assert it here so this module still stands up if keyd ever goes away.
  hardware.uinput.enable = true;
  users.users.dani.extraGroups = [ "input" "uinput" ];
}
