{
  config,
  pkgs,
  ...
}:

{
  programs.zellij = {
    enable = true;
    settings = {
      theme = "tokyo-night-dark";
    };
  };
}

