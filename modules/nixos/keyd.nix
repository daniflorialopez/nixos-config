{ pkgs, ... }:
{
  services.keyd = {
    enable = true;

    keyboards.default = {
      ids = [ "*" ]; # all keyboards
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

