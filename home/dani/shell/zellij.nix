{
  config,
  pkgs,
  theme,
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
          base = theme.hex.muted;
          background = theme.hex.bg;
          emphasis_0 = theme.hex.attention;
          emphasis_1 = theme.hex.successText;
          emphasis_2 = theme.hex.accentText;
          emphasis_3 = theme.hex.purple;
        };
        text_selected = {
          base = theme.hex.fg;
          background = theme.hex.selection;
          emphasis_0 = theme.hex.attention;
          emphasis_1 = theme.hex.successText;
          emphasis_2 = theme.hex.accentText;
          emphasis_3 = theme.hex.purple;
        };
        ribbon_selected = {
          # active tab / mode pill: dark text on Tokyo Night blue
          base = theme.hex.bg;
          background = theme.hex.accent;
          emphasis_0 = theme.hex.critical;
          emphasis_1 = theme.hex.bg;
          emphasis_2 = theme.hex.bg;
          emphasis_3 = theme.hex.bg;
        };
        ribbon_unselected = {
          base = theme.hex.muted;
          background = theme.hex.surface;
          emphasis_0 = theme.hex.attention;
          emphasis_1 = theme.hex.fg;
          emphasis_2 = theme.hex.muted;
          emphasis_3 = theme.hex.muted;
        };
        table_title = {
          base = theme.hex.accentText;
          background = theme.hex.bg;
          emphasis_0 = theme.hex.attention;
          emphasis_1 = theme.hex.successText;
          emphasis_2 = theme.hex.accentText;
          emphasis_3 = theme.hex.purple;
        };
        table_cell_selected = {
          base = theme.hex.fg;
          background = theme.hex.selection;
          emphasis_0 = theme.hex.attention;
          emphasis_1 = theme.hex.successText;
          emphasis_2 = theme.hex.accentText;
          emphasis_3 = theme.hex.purple;
        };
        table_cell_unselected = {
          base = theme.hex.muted;
          background = theme.hex.bg;
          emphasis_0 = theme.hex.attention;
          emphasis_1 = theme.hex.successText;
          emphasis_2 = theme.hex.accentText;
          emphasis_3 = theme.hex.purple;
        };
        list_selected = {
          base = theme.hex.fg;
          background = theme.hex.selection;
          emphasis_0 = theme.hex.attention;
          emphasis_1 = theme.hex.successText;
          emphasis_2 = theme.hex.accentText;
          emphasis_3 = theme.hex.purple;
        };
        list_unselected = {
          base = theme.hex.muted;
          background = theme.hex.bg;
          emphasis_0 = theme.hex.attention;
          emphasis_1 = theme.hex.successText;
          emphasis_2 = theme.hex.accentText;
          emphasis_3 = theme.hex.purple;
        };
        frame_selected = {
          # active pane frame: blue accent, matching the dark-surface rule
          base = theme.hex.accent;
          background = theme.hex.bg;
          emphasis_0 = theme.hex.attention;
          emphasis_1 = theme.hex.warning;
          emphasis_2 = theme.hex.critical;
          emphasis_3 = theme.hex.purple;
        };
        frame_unselected = {
          # same muted slate as Hyprland's inactive window border
          base = theme.hex.slate;
          background = theme.hex.bg;
          emphasis_0 = theme.hex.attention;
          emphasis_1 = theme.hex.warning;
          emphasis_2 = theme.hex.critical;
          emphasis_3 = theme.hex.purple;
        };
        frame_highlight = {
          # attention (resize, pinned, search hits): the sunset pop
          base = theme.hex.attention;
          background = theme.hex.bg;
          emphasis_0 = theme.hex.warning;
          emphasis_1 = theme.hex.attention;
          emphasis_2 = theme.hex.attention;
          emphasis_3 = theme.hex.attention;
        };
        exit_code_success = {
          base = theme.hex.success;
          background = theme.hex.bg;
          emphasis_0 = theme.hex.successText;
          emphasis_1 = theme.hex.success;
          emphasis_2 = theme.hex.success;
          emphasis_3 = theme.hex.success;
        };
        exit_code_error = {
          base = theme.hex.criticalText;
          background = theme.hex.bg;
          emphasis_0 = theme.hex.critical;
          emphasis_1 = theme.hex.criticalText;
          emphasis_2 = theme.hex.criticalText;
          emphasis_3 = theme.hex.criticalText;
        };
        multiplayer_user_colors = [
          theme.hex.attention
          theme.hex.accent
          theme.hex.successText
          theme.hex.purple
          theme.hex.warning
          theme.hex.criticalText
          theme.hex.teal
          theme.hex.fg
          theme.hex.success
          theme.hex.accentText
        ];
      };
    };
  };
}
