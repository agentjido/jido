# Architecture decision records

This directory records decisions that constrain the Jido V3 architecture. The [module dependency map](../architecture/module-dependency-map.md) remains the living map of namespace ownership and dependency direction.

## Records

| ADR | Status | Decision |
|---|---|---|
| [0001](0001-one-mix-project-and-one-otp-application.md) | Accepted | Keep one Mix project and one OTP application |
| [0002](0002-restore-or-create-durable-agent-activation.md) | Superseded | Restore or create durable Agent activation |
| [0003](0003-atomic-inactive-agent-upgrade.md) | Accepted | Upgrade an inactive saved Agent atomically |

| [0004](0004-passive-catalog-reference-resolution.md) | Accepted | Keep Catalog passive and resolve registered values for hydration |

## Backlog

Create records for these accepted or proposed decisions:

- Organize ownership by `Jido.*` concept, not by former package.
- Enforce one-way dependency layers with Reach.
- Give each V3 concept one canonical API owner. Do not add compatibility shims.
- Use Flow as the Agent behavior boundary.
- Give AgentServer ownership of Turn lifecycle, commit, and post-commit effects.
- Keep Flow meaning the same in direct, managed, and durable execution.
- Split continuation ownership across Exec values, AgentServer lifecycle, and Persistence storage.
- Publish stable semantic events without giving observability code control of behavior.
- Use one W3C Trace representation.
- Keep validation, authorization, process isolation, and sandboxing as separate controls.

## Format

Copy [0000-template.md](0000-template.md). Use the next four-digit number. Keep one decision in each record. Add the record to this index in the same change.

Use these statuses: `Proposed`, `Accepted`, `Rejected`, and `Superseded`.
