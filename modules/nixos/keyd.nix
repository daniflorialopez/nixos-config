{ pkgs, ... }:
{
  services.keyd = {
    enable = true;

    keyboards.default = {
      # `*` = every keyboard; `-736e` = except the Sonuscape vendor id, which
      # is the virtual keyboard Mouseless creates to replay the keys it does
      # not swallow (see modules/nixos/mouseless.nix). Without the exclusion
      # keyd grabs that virtual device and feeds its own output back into it,
      # and the loop wedges the keyboard until one of the two is killed.
      # A bare vendor id is enough: keyd prefix-matches against
      # "<vendor>:<product>:<uid>" (config_check_match in keyd's config.c).
      ids = [ "*" "-736e" ];
      settings = {
        meta = {
          # Super+C / Super+V -> Ctrl+Insert / Shift+Insert
          c = "C-insert";
          v = "S-insert";
        };
      };
    };
  };

  environment.systemPackages = [ pkgs.keyd ];
}

