{ pkgs, ... }:

let
  # Single source of truth: the command pages the same doc that lives in the
  # repo, so the on-box copy and the git copy can't drift. Baked onto the
  # system (PATH) so it works from the bare safe-graphics rescue TTY, where
  # there's no browser and no memory of where the file is — just type `rescue`.
  doc = ../../docs/rescue-blackscreen.md;
  rescue = pkgs.writeShellApplication {
    name = "rescue";
    runtimeInputs = [ pkgs.less ];
    text = ''
      exec less -R ${doc}
    '';
  };
in
{
  environment.systemPackages = [ rescue ];
}
