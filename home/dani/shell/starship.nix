{ ... }:

{
  programs.starship = {
    enable = true;
    enableFishIntegration = true;

    settings = {
      add_newline = false;

      format = "$directory$git_branch$git_status$character";

      # Lock the named colors to Tokyo Night instead of whatever the
      # terminal maps them to
      # Tokyo Night hues, AAA-calibrated for text (>=7:1 on #1a1b26).
      # No cyan in the prompt: Dani can't tell it apart from blue/white
      # fast — its roles went to the sunset orange (max hue distance
      # from blue, matches the desktop accent).
      palette = "tokyo_night";
      palettes.tokyo_night = {
        cyan = "#4fd6be"; # teal, for any straggler "cyan" style
        blue = "#7ea5f7";
        green = "#9ece6a";
        yellow = "#e0af68";
        red = "#f88298";
        purple = "#bb9af7";
        orange = "#ff9e64";
      };

      directory = {
        truncation_length = 3;
      	truncate_to_repo = true;
        # blue accent: the terminal is its own dark surface, so it takes
        # the Tokyo Night blue like waybar — sunset stays on the ❯ pop
	      style = "bold blue";
	      format = "[$path]($style)";
      };

      git_branch = {
        format = " [$branch]($style)";
        # directory + git segment form one blue "location" block: path in
        # the filesystem (bold), branch in git history (italic)
        style = "italic blue";
        truncation_length = 20;
      };

      git_status = {
        format = "([ $all_status]($style))";
        # same blue as the branch: the whole git segment stays one unit
        style = "blue";
	      conflicted = "⚔ ";
        ahead      = "↑";
        behind     = "↓";
        diverged   = "↕";
        untracked  = "?";
      	stashed    = "\\$";
        modified   = "!";
        staged     = "+";
        renamed    = "» ";
        deleted    = "🗑 ";
      };

      character = {
        success_symbol = " [❯](bold orange)";
        error_symbol   = " [✗](bold red)";
        vimcmd_symbol  = " [❮](bold green)";
        vimcmd_visual_symbol = " [❮](bold purple)";
        vimcmd_replace_symbol = " [❮](bold red)";
        vimcmd_replace_one_symbol = " [❮](bold red)";
      };

      ################
      # Disable noise
      ################

      username.disabled         = true;
      hostname.disabled         = true;
      time.disabled             = true;
      cmd_duration.disabled     = true;
      nodejs.disabled           = true;
      python.disabled           = true;
      rust.disabled             = true;
      java.disabled             = true;
      docker_context.disabled   = true;
      aws.disabled              = true;
      gcloud.disabled           = true;
      kubernetes.disabled       = true;
      terraform.disabled        = true;
      package.disabled          = true;
    };
  };
}

