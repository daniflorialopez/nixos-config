# Acceptance Checklist

## Visual coherence

- [ ] shared typography, spacing, radii, semantic colors, animation language
- [ ] GTK and Qt feel related
- [ ] cursor/icons are consistent
- [ ] browser/terminal/editor fit the desktop
- [ ] lock/greeter/Plymouth share the same visual family

## Dynamic theming

- [ ] wallpaper changes interactively
- [ ] transition is smooth
- [ ] palette updates safely
- [ ] shell/terminal/GTK/Qt update safely
- [ ] browser/editor remain readable
- [ ] exactly one runtime theme authority

## Shell

- [ ] bar
- [ ] launcher
- [ ] recovery terminal
- [ ] notifications/history
- [ ] control center
- [ ] OSD
- [ ] clipboard
- [ ] media
- [ ] power menu
- [ ] shell restart without session loss

## Hyprland

- [ ] organized window/monitor rules
- [ ] centralized animation curves
- [ ] deliberate blur/transparency
- [ ] gaming rules
- [ ] readable auth dialogs
- [ ] experimental effects/plugins independently disableable

## Profiles

- [ ] daily
- [ ] cinematic
- [ ] showcase
- [ ] gaming
- [ ] battery
- [ ] reduced-motion

## Keyboard-first

- [ ] apps/windows/workspaces/special workspaces
- [ ] file/clipboard/emoji search
- [ ] volume/brightness/Wi-Fi/Bluetooth
- [ ] screenshots/recording
- [ ] power menu
- [ ] wallpaper/profile switching
- [ ] Nix rebuild entry point
- [ ] emergency terminal

## Login / idle / power

- [ ] greeter independent of desktop shell
- [ ] lock and suspend/resume work
- [ ] idle/DPMS policy works
- [ ] polkit works
- [ ] logout/reboot/shutdown graceful

## Performance / reliability

- [ ] idle CPU/memory/GPU/VRAM acceptable
- [ ] animations smooth
- [ ] gaming mode removes unnecessary effects
- [ ] expensive effects optional
- [ ] session usable if shell/wallpaper/theme service fails
- [ ] no duplicate notification/clipboard daemons
- [ ] no overlapping config ownership
- [ ] rollback documented
- [ ] known-good generation preserved

## Repository quality

- [ ] modules logically separated
- [ ] fast-moving inputs pinned
- [ ] no imperative installer required
- [ ] runtime state excluded from Git where appropriate
- [ ] ownership documented
- [ ] major changes are reviewable commits
- [ ] a new AI agent can understand the architecture from docs alone
