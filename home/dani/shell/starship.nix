{ ... }:

{
  programs.starship = {
    enable = true;
    enableFishIntegration = true;

    settings = {
      add_newline = false;

      format = "$directory$git_branch$git_status$character";

      directory = {
        truncation_length = 3;
      	truncate_to_repo = true;
	      style = "cyan";
	      format = "[$path]($style)";
      };

      git_branch = {
        format = " [$branch]($style)";
        style = "italic cyan";
        truncation_length = 20;
      };

      git_status = {
        format = "([ $all_status]($style))";
        style = "cyan";
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
        success_symbol = " [❯](bold cyan)";
        error_symbol   = " [✗](bold cyan)";
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

