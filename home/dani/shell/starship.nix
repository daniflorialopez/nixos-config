{ ... }:

{
  programs.starship = {
    enable = true;
    enableFishIntegration = true;

    settings = {
      add_newline = false;

      format = "$directory$git_branch$git_status$line_break$character";

      directory = {
        truncation_length = 3;
	truncate_to_repo = true;
	style = "cyan";
	format = "[$path]($style)";
      };

      git_branch = {
        format = " on [$branch]($style)";
        style = "purple";
        truncation_length = 20;
      };

      git_status = {
        format = " [$all_status]($style)";
        style = "red";
        conflicted = "⚔";
        ahead      = "↑";
        behind     = "↓";
        diverged   = "↕";
        untracked  = "?";
        modified   = "!";
        staged     = "+";
        renamed    = "»";
        deleted    = "🗑";
      };

      character = {
        success_symbol = "❯ ";
        error_symbol   = "[❯](bold red) ";
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

