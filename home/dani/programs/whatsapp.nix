{ config, pkgs, ... }:

let
  profileDir = "${config.home.homeDirectory}/.local/share/chromium-whatsapp";

  whatsapp-web = pkgs.writeShellApplication {
    name = "whatsapp-web";
    runtimeInputs = [ pkgs.chromium ];
    text = ''
      exec ${pkgs.chromium}/bin/chromium \
        --ozone-platform-hint=auto \
        --enable-wayland-ime \
        --password-store=basic \
        --app=https://web.whatsapp.com \
        --user-data-dir="${profileDir}" \
        "$@"
    '';
  };
in
{
  home.packages = [
    whatsapp-web
  ];

  xdg.desktopEntries.whatsapp-web = {
    name = "WhatsApp Web";
    exec = "${whatsapp-web}/bin/whatsapp-web";
    terminal = false;
    categories = [ "Network" "InstantMessaging" ];
    startupNotify = true;
  };

  wayland.windowManager.hyprland.settings.bindd = [
    "$mod SHIFT, W, WhatsApp Web, exec, ${whatsapp-web}/bin/whatsapp-web"
  ];
}
