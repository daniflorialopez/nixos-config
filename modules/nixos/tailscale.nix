{ ... }:

{
  services.tailscale = {
    enable = true;

    # Opens Tailscale's UDP tunnel port, normally 41641.
    openFirewall = true;
  };
}
