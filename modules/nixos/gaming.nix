{ pkgs, ... }:

{
  programs.steam = {
    enable = true;
    # GE-Proton as a selectable compat tool: eFootball freezes at launch
    # on newer stock Proton (server handshake), GE gets better reports
    extraCompatPackages = [ pkgs.proton-ge-bin ];
  };

  # CPU performance governor while a game runs; opt in per game with
  # the "gamemoderun %command%" launch option in Steam
  programs.gamemode.enable = true;

  environment.systemPackages = with pkgs; [

  ];
}
