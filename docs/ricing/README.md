# NixOS Ricing Documentation

This directory is the design, architecture, implementation, and recovery knowledge base for the desktop-rice project.

## Read order

1. `../../RICE_PLAN.md` — master objective and target architecture.
2. `00-ai-context.md` — AI-agent working rules.
3. `01-current-state.md` — actual repository inventory; fill this first.
4. `02-visual-system.md` — shared visual language.
5. `03-component-catalog.md` — responsibilities and candidate tools.
6. `04-roadmap.md` — phased implementation order.
7. `05-nix-architecture.md` — ownership and declarative design.
8. `06-decisions.md` — architectural decision log.
9. `07-testing-and-rollback.md` — validation and recovery policy.
10. `08-implementation-tracker.md` — project status.
11. `09-acceptance-checklist.md` — definition of done.
12. `10-ideas-backlog.md` — optional ambitious ideas.
13. `11-upstream-reference-map.md` — upstream projects to verify.
14. `12-ai-task-template.md` — reusable task format for coding agents.

## Minimum AI context

Before implementing a ricing change, read:

```text
AGENTS.md
RICE_PLAN.md
docs/ricing/00-ai-context.md
docs/ricing/01-current-state.md
docs/ricing/04-roadmap.md
docs/ricing/05-nix-architecture.md
docs/ricing/07-testing-and-rollback.md
```

`01-current-state.md` is intentionally a template until the real repository is inspected. Do not treat design documentation as proof of what is currently configured.
