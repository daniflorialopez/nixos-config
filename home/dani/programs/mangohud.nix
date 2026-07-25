{ ... }:

{
  # Overlay for debugging Steam/Proton games. Just installs the mangohud
  # package (incl. 32-bit libs for older Proton titles); the overlay itself
  # is configured inline per game via MANGOHUD_CONFIG in the Steam launch
  # options, e.g.:
  #   PROTON_LOG=1 SDL_VIDEODRIVER=x11 \
  #   MANGOHUD_CONFIG=fps,frame_timing=1,gpu_name,gpu_stats,gpu_temp,cpu_stats,cpu_temp,vram,ram,vulkan_driver \
  #   gamemoderun mangohud %command%
  programs.mangohud.enable = true;
}
