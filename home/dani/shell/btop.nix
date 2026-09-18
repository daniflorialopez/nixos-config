{ theme, ... }:

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
    theme[main_bg]="${theme.hex.bg}"
    theme[main_fg]="${theme.hex.fg}"
    theme[title]="${theme.hex.fg}"
    theme[hi_fg]="${theme.hex.accent}"
    theme[selected_bg]="${theme.hex.selection}"
    theme[selected_fg]="${theme.hex.fg}"
    theme[inactive_fg]="${theme.hex.slate}"
    theme[graph_text]="${theme.hex.muted}"
    theme[meter_bg]="${theme.hex.surface}"
    theme[proc_misc]="${theme.hex.accent}"

    theme[cpu_box]="${theme.hex.slate}"
    theme[mem_box]="${theme.hex.slate}"
    theme[net_box]="${theme.hex.slate}"
    theme[proc_box]="${theme.hex.slate}"
    theme[div_line]="${theme.hex.slate}"

    # temperature: calm green until it isn't
    theme[temp_start]="${theme.hex.success}"
    theme[temp_mid]="${theme.hex.warning}"
    theme[temp_end]="${theme.hex.critical}"

    # cpu load: the sunset gradient, like the active window border
    theme[cpu_start]="${theme.hex.warning}"
    theme[cpu_mid]="${theme.hex.attention}"
    theme[cpu_end]="${theme.hex.critical}"

    # memory: free/available stay green, cached goes teal (the palette's
    # "cyan"), used climbs the sunset
    theme[free_start]="${theme.hex.success}"
    theme[free_mid]="${theme.hex.successText}"
    theme[free_end]="${theme.hex.successText}"
    theme[cached_start]="${theme.hex.teal}"
    theme[cached_mid]="${theme.hex.teal}"
    theme[cached_end]="${theme.hex.tealDim}"
    theme[available_start]="${theme.hex.success}"
    theme[available_mid]="${theme.hex.successText}"
    theme[available_end]="${theme.hex.successText}"
    theme[used_start]="${theme.hex.warning}"
    theme[used_mid]="${theme.hex.attention}"
    theme[used_end]="${theme.hex.critical}"

    # network: blue family down, orange family up (accent vs attention)
    theme[download_start]="${theme.hex.searchMatch}"
    theme[download_mid]="${theme.hex.accent}"
    theme[download_end]="${theme.hex.brightBlue}"
    theme[upload_start]="${theme.hex.warning}"
    theme[upload_mid]="${theme.hex.attention}"
    theme[upload_end]="${theme.hex.critical}"

    theme[process_start]="${theme.hex.accent}"
    theme[process_mid]="${theme.hex.purple}"
    theme[process_end]="${theme.hex.critical}"
  '';
}
