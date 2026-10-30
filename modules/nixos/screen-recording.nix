{ ... }:

{
  # gpu-screen-recorder (gap item 10b): screen recording and instant replay
  # encoded on the GPU (NVENC on legionix), so recording costs almost no CPU.
  #
  # The NixOS module, not just the package, because capturing the screen
  # through KMS needs CAP_SYS_ADMIN: the module installs gsr-kms-server as a
  # setcap wrapper, which is what makes recording start without a password
  # prompt. The scripts, binds and the replay service live in
  # home/dani/wm/recording.nix and switch themselves off on hosts without this.
  programs.gpu-screen-recorder.enable = true;
}
