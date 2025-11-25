{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    wireshark
    nmap
    # add others like burp (later apparently with allowUnfree and overlays),
    # aircrack-ng, hydra, johntheripper...
  ];

  programs.wireshark.enable = true;
}

