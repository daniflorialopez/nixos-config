{ pkgs, ... }:

{
  programs.steam = {
    enable = true;
    # GE-Proton as a selectable compat tool: eFootball freezes at launch
    # on newer stock Proton (server handshake), GE gets better reports
    extraCompatPackages = [ pkgs.proton-ge-bin ];
    # libgamemode.so (+ mangohud) inside Steam's FHS sandbox. gamemoderun
    # preloads libgamemodeauto.so fine, but its dlopen of libgamemode.so
    # failed inside the sandbox, so GameMode never engaged and the CPU
    # stayed on the powersave governor during matches.
    extraPackages = with pkgs; [ gamemode mangohud ];
  };

  # CPU performance governor while a game runs; opt in per game with
  # the "gamemoderun %command%" launch option in Steam
  programs.gamemode.enable = true;

  environment.systemPackages = with pkgs; [

  ];
}
