{ config, pkgs, ... }:

let
  # Build every host + flake check before switching. This repo is a
  # multi-host flake and a change must not break the non-NVIDIA host
  # (danix-hp) or the VM (danixos-vm); this catches that here instead of
  # after a switch. Defaults to ~/nixos-config; pass a flake path to override.
  checkAll = pkgs.writeShellApplication {
    name = "check-all";
    runtimeInputs = [ pkgs.nix ];
    text = ''
      flake="''${1:-$HOME/nixos-config}"
      echo "==> nix flake check $flake"
      nix flake check "$flake"

      # Verify the generated Hyprland config with the Hyprland binary from the
      # very same closure.
      #
      # Why this is worth the extra step: Hyprland does NOT fail on a bad config.
      # It records each bad line, drops that rule, queues a red error overlay,
      # and starts anyway. So a config mistake does not fail the build and does
      # not fail the switch - you discover it as a desktop with no window rules
      # and no layer blur, after you have already rebooted into it. On a machine
      # with no usable text console that is a bad place to find out.
      #
      # `--verify-config` parses and exits without starting a compositor. It
      # exists on 0.52.2 (verified) and on 0.55.4, so this keeps working across
      # the channel bump - which is precisely when it earns its keep, since the
      # windowrule/layerrule grammar changed in 0.53.
      verify_hypr() {
        local host="$1"
        local conf hypr out
        # danixos-vm has no Hyprland at all, so this attribute does not exist;
        # that is a clean skip, not a failure.
        conf="$(nix eval --raw \
          "$flake#nixosConfigurations.$host.config.home-manager.users.dani.xdg.configFile.\"hypr/hyprland.conf\".source" \
          2>/dev/null)" || return 0
        [ -n "$conf" ] || return 0
        hypr="$(nix eval --raw "$flake#nixosConfigurations.$host.config.programs.hyprland.package" 2>/dev/null)" || return 0

        # Both have to be realised, not merely evaluated: `nix eval --raw` yields
        # a store path that may not exist on disk yet. The toplevel build above
        # normally pulls both in, but building them explicitly means this
        # function is correct on its own rather than by side effect - and a
        # missing config file would otherwise make Hyprland fall back to its
        # built-in defaults and cheerfully report "config ok".
        nix build --no-link "$flake#nixosConfigurations.$host.config.programs.hyprland.package" || return 1
        nix build --no-link \
          "$flake#nixosConfigurations.$host.config.home-manager.users.dani.xdg.configFile.\"hypr/hyprland.conf\".source" || return 1
        [ -e "$conf" ] || { echo "==> FAIL: $host Hyprland config was not realised" >&2; return 1; }

        echo "==> verifying Hyprland config for $host"
        # --verify-config exits 0 even when it reports errors, so the exit code
        # is useless and the result has to be matched on its text.
        out="$("$hypr/bin/Hyprland" --verify-config -c "$conf" 2>&1)" || true
        if printf '%s\n' "$out" | grep -qx "config ok"; then
          return 0
        fi
        printf '%s\n' "$out" >&2
        echo "==> FAIL: $host has Hyprland config errors (see above)" >&2
        return 1
      }

      # Hyprland >=0.55 resolves its config by probing hyprland.lua BEFORE
      # hyprland.conf, so a stray Lua file silently outranks everything Home
      # Manager generates - no error, no warning, just stock Hyprland with
      # different keybinds and no monitor rules. Worse, if NEITHER exists it
      # generates a default Lua config. This warns rather than fails, because it
      # is user state rather than anything the flake controls.
      #
      # A nullglob array rather than `compgen -G`: writeShellApplication's bash
      # is built without programmable completion, so compgen is not a builtin
      # there and the check died with "compgen: command not found" on stderr
      # while check-all still reported OK. An interactive `bash -c 'compgen'`
      # does work, which is what made it look fine.
      shopt -s nullglob
      stray_lua=("$HOME"/.config/hypr/*.lua)
      shopt -u nullglob

      if [ ''${#stray_lua[@]} -gt 0 ]; then
        echo "==> WARNING: $HOME/.config/hypr contains a .lua file:" >&2
        printf '      %s\n' "''${stray_lua[@]}" >&2
        echo "    Hyprland >=0.55 prefers hyprland.lua over the home-manager-generated" >&2
        echo "    hyprland.conf, so this would silently replace your entire config." >&2
      fi

      for host in legionix danix-hp danixos-vm; do
        echo "==> building $host"
        nix build "$flake#nixosConfigurations.$host.config.system.build.toplevel" --no-link
        verify_hypr "$host"
      done
      echo "==> OK: all hosts build, Hyprland configs parse, and flake check passed"
    '';
  };

  # Tag every system generation with the commit it was built from:
  # `<host>-gen-<N>` -> the commit recorded by system.configurationRevision
  # (flake.nix). Answers "what was I running two switches ago?" from git, and
  # `git diff legionix-gen-236 legionix-gen-238` is what changed between them.
  #
  # Tags stay local: plain `git push` does not send them.
  #
  # Idempotent - it walks every generation and only creates missing tags - so
  # it is safe to fire as often as the path unit below likes. Skips, with a
  # line in the journal: generations from before the revision was recorded,
  # "-dirty" builds (no commit holds that exact tree), and commits this clone
  # does not have. Never moves an existing tag.
  tagGenerations = pkgs.writeShellApplication {
    name = "tag-generations";
    runtimeInputs = [ pkgs.git ];
    text = ''
      repo="''${1:-$HOME/nixos-config}"
      host=${config.networking.hostName}
      # Override only for testing against a fake profiles directory.
      profiles="''${TAG_GENERATIONS_PROFILES:-/nix/var/nix/profiles}"
      cd "$repo"

      shopt -s nullglob
      for link in "$profiles"/system-*-link; do
        n="''${link##*/system-}"
        n="''${n%-link}"
        tag="$host-gen-$n"

        # Exits 1 ("configuration revision is unknown") for older generations.
        rev="$("$link/sw/bin/nixos-version" --configuration-revision 2>/dev/null)" || continue

        case "$rev" in
          *-dirty)
            echo "$tag: built from uncommitted changes ($rev), not tagged"
            continue
            ;;
        esac

        if ! git cat-file -e "$rev^{commit}" 2>/dev/null; then
          echo "$tag: commit $rev is not in $repo, not tagged"
          continue
        fi

        if existing="$(git rev-parse -q --verify "refs/tags/$tag")"; then
          [ "$existing" = "$rev" ] || echo "$tag: already points at $existing, not $rev - left alone" >&2
          continue
        fi

        git tag "$tag" "$rev"
        echo "$tag -> $rev"
      done
    '';
  };
in
{
  # Run tag-generations whenever a generation appears, as the user who owns the
  # repo (git as root would leave root-owned files in .git).
  #
  # Watches the profiles DIRECTORY, not the `system` symlink: activation swaps
  # that link with an atomic rename, and inotify on the link follows it to the
  # old target, which never changes - tested, it does not fire. The directory
  # sees the rename. It also fires on `nh clean` deleting old links; harmless,
  # the script is idempotent.
  #
  # Defined for every user, but the condition limits it to one with the repo at
  # ~/nixos-config (the sddm greeter has a user manager too). Also runs once per
  # login, to catch switches made while logged out (e.g. over SSH).
  systemd.user.paths.tag-generations = {
    description = "Watch for new system generations to tag";
    wantedBy = [ "default.target" ];
    pathConfig.PathChanged = "/nix/var/nix/profiles";
  };

  systemd.user.services.tag-generations = {
    description = "Tag system generations with their source commit";
    wantedBy = [ "default.target" ];
    unitConfig.ConditionPathIsDirectory = "%h/nixos-config/.git";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${tagGenerations}/bin/tag-generations";
    };
  };

  # Show the store closure diff on every `nixos-rebuild switch` — what
  # packages were added, removed, or changed version. `nh os switch` already
  # prints this; the activation hook covers plain `nixos-rebuild switch` too.
  # It runs during activation while /run/current-system still points at the
  # old system, diffing it against the one being activated ($systemConfig).
  system.activationScripts.nvd-diff = {
    supportsDryActivation = false;
    text = ''
      if [ -e /run/current-system ]; then
        ${pkgs.nvd}/bin/nvd --nix-bin-dir=${config.nix.package}/bin \
          diff /run/current-system "$systemConfig" || true
      fi
    '';
  };

  # nvd on PATH for manual diffs (e.g. `nvd diff /run/current-system <path>`);
  # check-all for the pre-switch all-hosts build; tag-generations to run the
  # tagger by hand.
  environment.systemPackages = [ pkgs.nvd checkAll tagGenerations ];
}
