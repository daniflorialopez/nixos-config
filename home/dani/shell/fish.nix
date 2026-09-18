{ config, pkgs, theme, ... }:

let
  inherit (theme) hex noHash;
in

{ 
  programs.fzf = {
    enable = true;
    enableFishIntegration = false; # it is sourced later

    defaultCommand = "fd --type f --hidden --follow --exclude .git";

    # Tokyo Night, same role mapping as the rest of the desktop:
    # #283457 selection wash (fish/alacritty selection), orange for
    # matches (yazi find tier), blue for the prompt/position accents,
    # #a0a5c0 as the AAA-calibrated muted
    colors = {
      "fg" = hex.subtle;
      "fg+" = hex.fg;
      # NOT a colour. "-1" means "the terminal's own default", which is what
      # keeps the fzf pane transparent so the compositor glass shows through.
      # Never map this onto a palette role.
      "bg" = "-1";
      "bg+" = hex.selection;
      "hl" = hex.attention;
      "hl+" = hex.attention;
      "info" = hex.muted;
      "header" = hex.muted;
      "prompt" = hex.accent;
      "pointer" = hex.attention;
      "marker" = hex.success;
      "spinner" = hex.attention;
      "border" = hex.slate;
      "separator" = hex.slate;
      "scrollbar" = hex.slate;
    };

    historyWidgetOptions = [
      "--layout=reverse"
      "--height=40%"
      "--border"
    ];
  };

  programs.fish = {
    enable = true;

    # Abbreviation
    shellAbbrs = { 
      gs  = "git status";
      ga  = "git add -A";
      gcm = "git commit -m";
      gl  = "git log --oneline --graph --decorate";

      # Non-compliant packages with Comma syntax should follow the cowsay example below
      cowsay-run = "nix run nixpkgs#cowsay --";
      evtest-run = "sudo nix run nixpkgs#evtest --";
    };

    # Aliases
    shellAliases = {
      n = "nvim";   
      gl = "git log --oneline --graph --decorate";
      ll = "eza -lah --icons --group-directories-first";
      lg = "lazygit";
    };

    functions = {
      # Greeting colours also come from home/dani/theme/palette.nix.
      fish_greeting = ''
        set -l host (prompt_hostname)
        set -l user $USER
        set -l shell "fish"

        # Friendly aliases for ugly real hostnames
        switch $host
          case 'nixos-desktop'
            set host "desktop"
          case 'thinkpad'
            set host "laptop"
          case 'vps-01'
            set host "server"
        end

        # Detect remote session
        set -l is_remote 0
        if set -q SSH_TTY; or set -q SSH_CONNECTION; or set -q SSH_CLIENT
          set is_remote 1
        end

        # Restrained Tokyo Night palette
        set -l comment "${hex.slate}"
        set -l fg      "${hex.fg}"
        set -l blue    "${hex.accent}"
        set -l purple  "${hex.purple}"

        set -l role "local"
        set -l role_color $comment
        if test $is_remote -eq 1
          set role "remote"
          set role_color $purple
        end

        set_color $comment
        printf "╭─ "

        set_color $fg
        printf "%s" $user

        set_color $comment
        printf "@"

        set_color --bold $blue
        printf "%s" $host

        set_color $comment
        printf " · "

        set_color $role_color
        printf "%s" $role

        set_color $comment
        printf " · "

        set_color $comment
        printf "%s" $shell

        set_color normal
        echo
      '';
    };

    # Extra initialization when an interactive fish starts.
    #
    # The colour block below uses `noHash` from the palette, because fish takes
    # a BARE hex — no leading #, no quotes. That is worth knowing beyond fish:
    # it is the one colour syntax in this repo that a `#[0-9a-f]{6}` search does
    # not match, so before the palette layer these 21 values were invisible to
    # any audit that went looking for hex.
    #
    # Text roles throughout (accentText / criticalText rather than accent /
    # critical) — everything fish colours here is read, so it is held to the AAA
    # floor by the gate in home/dani/theme/default.nix. Two values are NOT
    # colours and must stay literal: `--underline` is a style, and fzf's
    # "bg" = "-1" above means "the terminal's own default".
    interactiveShellInit = ''
      # vi-style keybindings
      fish_vi_key_bindings

      # zoxide
      if type -q zoxide
        zoxide init fish | source
      end

      # ---- Tokyo Night syntax colors, calibrated to WCAG AAA (>=7:1
      # on #1a1b26) — same hues, lightness raised where canon fell short
      set -g fish_color_normal ${noHash.fg}
      set -g fish_color_command ${noHash.accentText}
      set -g fish_color_keyword ${noHash.purple}
      set -g fish_color_quote ${noHash.success}
      set -g fish_color_redirection ${noHash.attention}
      set -g fish_color_end ${noHash.attention}
      set -g fish_color_error ${noHash.criticalText}
      set -g fish_color_param ${noHash.fg}
      set -g fish_color_comment ${noHash.muted}
      set -g fish_color_operator ${noHash.attention}
      set -g fish_color_escape ${noHash.purple}
      set -g fish_color_autosuggestion ${noHash.muted}
      set -g fish_color_cancel ${noHash.criticalText}
      set -g fish_color_search_match --background=${noHash.searchMatch}
      set -g fish_color_selection --background=${noHash.selection}
      set -g fish_color_valid_path --underline

      set -g fish_pager_color_progress ${noHash.attention}
      set -g fish_pager_color_prefix ${noHash.attention}
      set -g fish_pager_color_completion ${noHash.fg}
      set -g fish_pager_color_description ${noHash.muted}
      set -g fish_pager_color_selected_background --background=${noHash.selection}
    '';

    shellInitLast = ''
      fzf --fish | source
    '';
  };
}
