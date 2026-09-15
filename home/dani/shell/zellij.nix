{
  config,
  pkgs,
  ...
}:

{
  programs.zellij = {
    enable = true;
    settings = {
      # Exit on SIGTERM instead of zellij's default "detach".
      #
      # The client and the server both live in the compositor's cgroup, so at
      # logout systemd SIGTERMs them, the server detaches on purpose, and
      # wayland-wm@Hyprland.service waits out its full TimeoutStopSec=10
      # before SIGKILLing it and failing with result 'timeout' — on every
      # shutdown. That failed exit is also what convinced SDDM the session had
      # crashed, back when logging out went through uwsm (see
      # logout-to-greeter.service in modules/nixos/desktop/sddm.nix).
      #
      # This costs less than it sounds: the session did not survive a logout
      # anyway, it was being SIGKILLed. What changes is closing a terminal
      # window while still logged in — that now ends the session rather than
      # leaving it detached. session_serialization is on by default, so the
      # tabs, panes, cwds and commands are still written out and `zellij
      # attach` can resurrect the layout; only live process state is lost.
      on_force_close = "quit";

      # Custom granular theme (zellij >= 0.40 style spec) instead of the
      # built-in tokyo-night-dark: the old 10-slot spec let zellij pick
      # its own UI mapping — bright green tab pills and frames. Here every
      # element is explicit. Design rule: dark surface -> blue accent
      # (like waybar); orange only as emphasis pop.
      theme = "tokyo-sunset";

      themes.tokyo-sunset = {
        text_unselected = {
          base = "#a0a5c0";
          background = "#1a1b26";
          emphasis_0 = "#ff9e64";
          emphasis_1 = "#b9f27c";
          emphasis_2 = "#7ea5f7";
          emphasis_3 = "#bb9af7";
        };
        text_selected = {
          base = "#c0caf5";
          background = "#283457";
          emphasis_0 = "#ff9e64";
          emphasis_1 = "#b9f27c";
          emphasis_2 = "#7ea5f7";
          emphasis_3 = "#bb9af7";
        };
        ribbon_selected = {
          # active tab / mode pill: dark text on Tokyo Night blue
          base = "#1a1b26";
          background = "#7aa2f7";
          emphasis_0 = "#f7768e";
          emphasis_1 = "#1a1b26";
          emphasis_2 = "#1a1b26";
          emphasis_3 = "#1a1b26";
        };
        ribbon_unselected = {
          base = "#a0a5c0";
          background = "#24283b";
          emphasis_0 = "#ff9e64";
          emphasis_1 = "#c0caf5";
          emphasis_2 = "#a0a5c0";
          emphasis_3 = "#a0a5c0";
        };
        table_title = {
          base = "#7ea5f7";
          background = "#1a1b26";
          emphasis_0 = "#ff9e64";
          emphasis_1 = "#b9f27c";
          emphasis_2 = "#7ea5f7";
          emphasis_3 = "#bb9af7";
        };
        table_cell_selected = {
          base = "#c0caf5";
          background = "#283457";
          emphasis_0 = "#ff9e64";
          emphasis_1 = "#b9f27c";
          emphasis_2 = "#7ea5f7";
          emphasis_3 = "#bb9af7";
        };
        table_cell_unselected = {
          base = "#a0a5c0";
          background = "#1a1b26";
          emphasis_0 = "#ff9e64";
          emphasis_1 = "#b9f27c";
          emphasis_2 = "#7ea5f7";
          emphasis_3 = "#bb9af7";
        };
        list_selected = {
          base = "#c0caf5";
          background = "#283457";
          emphasis_0 = "#ff9e64";
          emphasis_1 = "#b9f27c";
          emphasis_2 = "#7ea5f7";
          emphasis_3 = "#bb9af7";
        };
        list_unselected = {
          base = "#a0a5c0";
          background = "#1a1b26";
          emphasis_0 = "#ff9e64";
          emphasis_1 = "#b9f27c";
          emphasis_2 = "#7ea5f7";
          emphasis_3 = "#bb9af7";
        };
        frame_selected = {
          # active pane frame: blue accent, matching the dark-surface rule
          base = "#7aa2f7";
          background = "#1a1b26";
          emphasis_0 = "#ff9e64";
          emphasis_1 = "#e0af68";
          emphasis_2 = "#f7768e";
          emphasis_3 = "#bb9af7";
        };
        frame_unselected = {
          # same muted slate as Hyprland's inactive window border
          base = "#565f89";
          background = "#1a1b26";
          emphasis_0 = "#ff9e64";
          emphasis_1 = "#e0af68";
          emphasis_2 = "#f7768e";
          emphasis_3 = "#bb9af7";
        };
        frame_highlight = {
          # attention (resize, pinned, search hits): the sunset pop
          base = "#ff9e64";
          background = "#1a1b26";
          emphasis_0 = "#e0af68";
          emphasis_1 = "#ff9e64";
          emphasis_2 = "#ff9e64";
          emphasis_3 = "#ff9e64";
        };
        exit_code_success = {
          base = "#9ece6a";
          background = "#1a1b26";
          emphasis_0 = "#b9f27c";
          emphasis_1 = "#9ece6a";
          emphasis_2 = "#9ece6a";
          emphasis_3 = "#9ece6a";
        };
        exit_code_error = {
          base = "#f88298";
          background = "#1a1b26";
          emphasis_0 = "#f7768e";
          emphasis_1 = "#f88298";
          emphasis_2 = "#f88298";
          emphasis_3 = "#f88298";
        };
        multiplayer_user_colors = [
          "#ff9e64"
          "#7aa2f7"
          "#b9f27c"
          "#bb9af7"
          "#e0af68"
          "#f88298"
          "#4fd6be"
          "#c0caf5"
          "#9ece6a"
          "#7ea5f7"
        ];
      };
    };
  };
}
