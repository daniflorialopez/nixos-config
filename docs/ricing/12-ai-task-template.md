# AI Implementation Task Template

Use this when asking an AI coding agent to implement a ricing task.

## Task

Describe the concrete change.

## Goal

Describe what must be true when finished.

## Current owner

Which existing module/tool owns the responsibility now?

If unknown, the agent must inspect first.

## Desired owner

Which tool/module should own it afterward?

## Constraints

Examples:

- remain declarative;
- preserve systemd-boot;
- do not break gaming;
- keep shell-independent terminal access;
- do not conflict with Home Manager;
- follow existing repo structure.

## Files likely involved

List only when already known. Otherwise instruct the agent to discover them rather than inventing paths.

## Acceptance criteria

- [ ] Nix evaluation/rebuild path succeeds
- [ ] relevant service/component starts
- [ ] requested behavior works
- [ ] no duplicate daemon
- [ ] no ownership conflict
- [ ] fallback works
- [ ] rollback documented
- [ ] tracker updated
- [ ] decision log updated if architecture changed

## Testing

List the expected functional, visual, performance, and failure tests.

## Rollback

Describe the expected rollback path.

## Documentation updates

Update as appropriate:

- `01-current-state.md` when current architecture changes;
- `06-decisions.md` for architecture/ownership decisions;
- `08-implementation-tracker.md` for progress;
- `09-acceptance-checklist.md` only as criteria are actually satisfied.
