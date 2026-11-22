# hyprglass — a Hyprland plugin that puts liquid glass behind transparent
# windows (and, by namespace, layer surfaces): blur, refraction at the edges,
# a little chromatic aberration, specular highlights.
#
# Why this old version. A Hyprland plugin is compiled against the compositor's
# internals, and each hyprglass release fits exactly one Hyprland. This repo
# is on nixos-26.05, whose Hyprland is 0.55.4 (commit a0136d8); the plugin's
# own hyprpm.toml pairs that commit with this one, 7ff4064 ("hyprland 0.55.4
# -> hyprglass v0.6.4", June 2026). The current hyprglass (1.2.0) needs
# Hyprland 0.57.2, which no longer reads hyprland.conf at all: that is the
# 26.11 migration, and this file moves with it.
#
# What is missing here that later versions fixed, to be known if it misbehaves:
# a crash when an app closes a glass item after the plugin was unloaded or
# reloaded (0.9.0), and "a huge window, bar or menu no longer crashes
# Hyprland" (1.2.0).
#
# `nix build .#hyprglass`; the result is lib/libhyprglass.so, to be given to
# `hyprctl plugin load` or to the Hyprland config's `plugin =`.
{
  lib,
  hyprlandPlugins,
  fetchFromGitHub,
}:

hyprlandPlugins.mkHyprlandPlugin {
  pluginName = "hyprglass";
  version = "0.6.4";

  src = fetchFromGitHub {
    owner = "hyprnux";
    repo = "hyprglass";
    rev = "7ff4064cbed1ef6e6f703139fca4ec20ba0cbb5b";
    hash = "sha256-e60+3KjFJOIi4DqcpxkeADsdApV+Cso2mwRA9t1Fs3U=";
  };

  # The Makefile builds hyprglass.so in place and has no install target.
  installPhase = ''
    runHook preInstall
    install -Dm755 hyprglass.so $out/lib/libhyprglass.so
    runHook postInstall
  '';

  meta = {
    description = "Liquid glass for Hyprland: blur, refraction and highlights behind transparent windows";
    homepage = "https://github.com/hyprnux/hyprglass";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
  };
}
