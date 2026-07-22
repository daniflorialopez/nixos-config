{ ... }:

{
  # Tokyo Night btop with the desktop's role mapping: slate boxes, blue
  # accent for selection/highlights, and the sunset gradient
  # (yellow -> orange -> red, same as the Hyprland active border) on the
  # graphs that mean "load" — cpu, temperature, used memory.
  programs.btop = {
    enable = true;
    settings = {
      color_theme = "tokyo-sunset";
      # transparent main bg: btop inherits Alacritty's glass instead of
      # painting an opaque slab over it
      theme_background = false;
      vim_keys = true; # h/j/k/l, like fish/hyprland
    };
  };

  xdg.configFile."btop/themes/tokyo-sunset.theme".text = ''
    # Tokyo Night "sunset" — matches home/dani/wm/theme.nix palette
    theme[main_bg]="#1a1b26"
    theme[main_fg]="#c0caf5"
    theme[title]="#c0caf5"
    theme[hi_fg]="#7aa2f7"
    theme[selected_bg]="#283457"
    theme[selected_fg]="#c0caf5"
    theme[inactive_fg]="#565f89"
    theme[graph_text]="#a0a5c0"
    theme[meter_bg]="#24283b"
    theme[proc_misc]="#7aa2f7"

    theme[cpu_box]="#565f89"
    theme[mem_box]="#565f89"
    theme[net_box]="#565f89"
    theme[proc_box]="#565f89"
    theme[div_line]="#565f89"

    # temperature: calm green until it isn't
    theme[temp_start]="#9ece6a"
    theme[temp_mid]="#e0af68"
    theme[temp_end]="#f7768e"

    # cpu load: the sunset gradient, like the active window border
    theme[cpu_start]="#e0af68"
    theme[cpu_mid]="#ff9e64"
    theme[cpu_end]="#f7768e"

    # memory: free/available stay green, cached goes teal (the palette's
    # "cyan"), used climbs the sunset
    theme[free_start]="#9ece6a"
    theme[free_mid]="#b9f27c"
    theme[free_end]="#b9f27c"
    theme[cached_start]="#4fd6be"
    theme[cached_mid]="#4fd6be"
    theme[cached_end]="#53c7ad"
    theme[available_start]="#9ece6a"
    theme[available_mid]="#b9f27c"
    theme[available_end]="#b9f27c"
    theme[used_start]="#e0af68"
    theme[used_mid]="#ff9e64"
    theme[used_end]="#f7768e"

    # network: blue family down, orange family up (accent vs attention)
    theme[download_start]="#3d59a1"
    theme[download_mid]="#7aa2f7"
    theme[download_end]="#7da6ff"
    theme[upload_start]="#e0af68"
    theme[upload_mid]="#ff9e64"
    theme[upload_end]="#f7768e"

    theme[process_start]="#7aa2f7"
    theme[process_mid]="#bb9af7"
    theme[process_end]="#f7768e"
  '';
}
