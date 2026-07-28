# modules/nixos/efootball-block.nix
#
# Opt-in, per-session block of eFootball's TCP relay matchmaking path.
#
# Matchmaking can land a match on one of three transports: direct P2P,
# peer-server-peer over UDP, or peer-server-peer over TCP. The TCP relay
# path is the laggy one. Dropping outbound traffic to the relay's TCP
# ports means matchmaking never settles there and falls back to UDP/P2P.
#
# Port intel is community-sourced and undocumented by Konami (may go
# stale): TCP 30000-35000 is the relay range, TCP 5736 was added as a
# relay port after the 4.3 update.
#   https://github.com/SuNingXJBT/eFootball_Block_TCP_Matches
#
# Design:
#   - Own nft table (inet efb), not an addition to the NixOS firewall
#     ruleset: independent, added/removed atomically, no need to flip
#     networking.nftables.enable.
#   - systemd oneshot + RemainAfterExit gives start/stop semantics and
#     free state tracking via `systemctl is-active`.
#   - Polkit scopes a passwordless start/stop of *this one unit* to the
#     wheel group, so the waybar click (running as the user) works with
#     no password prompt and without a broad NOPASSWD sudoers rule.
#   - Deliberately NOT wantedBy multi-user.target: the safe default is
#     off, and a reboot clears the block. A 5000-port TCP block left on
#     permanently would eventually break something unrelated and be very
#     hard to diagnose — hence the toggle.
#
# Imported by the gaming host (legionix) only.
{ pkgs, ... }:
let
  ruleset = pkgs.writeText "efootball-block.nft" ''
    table inet efb {
      chain out {
        type filter hook output priority filter; policy accept;
        tcp dport { 5736, 30000-35000 } drop
      }
    }
  '';
in
{
  # The Hyprland module already pulls polkit in; make the dependency
  # explicit since the toggle is useless without it.
  security.polkit.enable = true;

  systemd.services.efootball-block = {
    description = "Block eFootball TCP relay matchmaking";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.nftables}/bin/nft -f ${ruleset}";
      # leading '-' so stopping an already-absent table isn't a unit failure
      ExecStop = "-${pkgs.nftables}/bin/nft delete table inet efb";
    };
    # deliberately NOT wantedBy multi-user.target - this is opt-in per session
  };

  # Passwordless start/stop of this single unit for the seated user, so a
  # waybar click can flip it. Scoped to the exact unit + wheel group.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "efootball-block.service" &&
          subject.isInGroup("wheel")) {
        return polkit.Result.YES;
      }
    });
  '';
}
