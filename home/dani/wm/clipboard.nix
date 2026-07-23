{ pkgs, ... }:

let
  # Copy a secret (stdin) so it NEVER enters clipboard history: elephant's
  # clipboard provider records on wl-paste change events and ignores the
  # x-kde-passwordManagerHint mime type entirely (checked source, 2026-07),
  # so the only reliable exclusion is pausing the recorder around the copy.
  # Missed events are not re-scanned on unpause, which makes the pause
  # window a real guarantee, not a race. The clipboard itself auto-clears
  # after 45s unless something else was copied in the meantime.
  # Usage: bw get password <item> | pwcopy
  pwcopy = pkgs.writeShellApplication {
    name = "pwcopy";
    # elephant comes from the session PATH (programs.elephant), not nixpkgs
    runtimeInputs = with pkgs; [ wl-clipboard libnotify coreutils ];
    text = ''
      secret="$(cat)"
      if [ -z "$secret" ]; then
        echo "pwcopy: empty input, nothing copied" >&2
        exit 1
      fi

      elephant activate 'clipboard;;pause;;'
      trap "elephant activate 'clipboard;;unpause;;'" EXIT

      printf '%s' "$secret" | wl-copy
      # let the clipboard-change event reach elephant while still paused
      sleep 1

      notify-send -t 5000 "Secret copied" "Not recorded in history. Clipboard clears in 45s."

      (
        sleep 45
        if [ "$(wl-paste -n 2>/dev/null || true)" = "$secret" ]; then
          wl-copy --clear
          notify-send -t 3000 "Clipboard cleared" "The secret is gone."
        fi
      ) >/dev/null 2>&1 &
    '';
  };

  # Panic button / post-hoc cleanup: empty the entire history and the
  # live clipboard (for secrets that arrived outside pwcopy, e.g. copied
  # from the Firefox Bitwarden extension).
  clipboardWipe = pkgs.writeShellApplication {
    name = "clipboard-wipe";
    runtimeInputs = with pkgs; [ wl-clipboard libnotify ];
    text = ''
      elephant activate 'clipboard;;remove_all;;'
      wl-copy --clear
      notify-send -t 3000 "Clipboard wiped" "History and current clipboard emptied."
    '';
  };
in
{
  # Elephant merges this over its defaults. auto_cleanup is both the max
  # age and the sweep interval (minutes): entries older than 12h are
  # deleted, so nothing lingers for days even without a manual wipe.
  # The history db (~/.cache/elephant/clipboard.gob) is plaintext — the
  # TTL bounds exposure until the disk is LUKS-encrypted.
  xdg.configFile."elephant/clipboard.toml".text = ''
    auto_cleanup = 720
    max_items = 100
  '';

  home.packages = [
    pwcopy
    clipboardWipe
  ];
}
