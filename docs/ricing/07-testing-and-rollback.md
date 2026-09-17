# Testing and Rollback Policy

Ricing changes must remain cheap to recover from.

## Before risky changes

- commit the working state;
- ensure a known-good NixOS generation exists;
- change one architecture concern at a time;
- avoid deleting the old working path immediately.

## Validation

Use the repository's existing commands. Typical commands may include:

```bash
nix flake check
sudo nixos-rebuild test --flake .#<host>
sudo nixos-rebuild switch --flake .#<host>
```

Do not assume the hostname; inspect the flake.

If Home Manager is integrated into NixOS, do not bypass the repository's normal rebuild path without reason.

## Visual regression checks

After UI changes, test:

- app launch;
- launcher;
- emergency terminal shortcut;
- notifications;
- volume/brightness;
- clipboard;
- lock/unlock;
- suspend/resume;
- logout;
- external display;
- wallpaper/theme changes;
- shell restart;
- reboot when relevant.

## Performance checks

Compare before/after:

- idle CPU;
- memory;
- GPU usage;
- VRAM;
- compositor frame timing;
- subjective responsiveness;
- game performance when relevant.

## Failure tests

### Shell crash
Expected: Hyprland remains running; direct terminal works; shell can be restarted.

### Wallpaper daemon crash
Expected: session stays usable and readable.

### Theme generation failure
Expected: last valid theme remains usable; no critical config is truncated.

### Notification failure
Expected: session remains usable and daemon can restart independently.

### Plugin incompatibility
Expected: plugin can be disabled without rewriting the whole desktop.

## Rollback hierarchy

1. restart affected service/component;
2. disable feature flag;
3. revert Git commit;
4. rebuild previous repo state;
5. boot known-good NixOS generation;
6. use TTY/live-media recovery only if necessary.

## Boot-critical separation

Bootloader, EFI, initrd, disk-layout, and encryption changes must not be bundled with cosmetic ricing changes.
