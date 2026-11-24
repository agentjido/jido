# Architecture decision records

This directory records decisions that constrain the Jido V3 architecture. The [module dependency map](../architecture/module-dependency-map.md) remains the living map of namespace ownership and dependency direction.

## Records

| ADR | Status | Decision |
|---|---|---|
| [0001](0001-one-mix-project-and-one-otp-application.md) | Accepted | Keep one Mix project and one OTP application |
| [0002](0002-restore-or-create-durable-agent-activation.md) | Superseded | Restore or create durable Agent activation |
| [0003](0003-atomic-inactive-agent-upgrade.md) | Accepted | Upgrade an inactive saved Agent atomically |
| [0004](0004-passive-catalog-reference-resolution.md) | Accepted | Keep Catalog passive and resolve registered values for hydration |
| [0005](0005-activation-local-declared-subtree-removal.md) | Accepted | Remove one declared subtree from the current activation |
| [0006](0006-local-agent-ownership-transfer.md) | Accepted | Keep dynamic Agent ownership local and activation-scoped |
| [0007](0007-deterministic-schema-field-order.md) | Accepted | Keep object schema field order stable across builds |
| [0008](0008-stateful-recurring-intervals.md) | Accepted | Keep static and stateful recurring intervals in Timer |
| [0009](0009-durable-topology-acceptance.md) | Proposed | Commit durable topology sends and receiver acceptance in Agent records |
| [0010](0010-exec-task-ownership-and-admission.md) | Accepted | Use Runic task ownership and bound immediate admission |
| [0011](0011-direct-durable-operation-ownership.md) | Accepted | Admit one direct Durable operation per reference |
| [0012](0012-agent-route-input-preparation.md) | Accepted | Apply Plugin policy before executable input validation |
| [0013](0013-telemetry-proof-ownership.md) | Accepted | Align Telemetry and Trace proof with Reach |
| [0014](0014-thread-proof-ownership.md) | Accepted | Give Thread and Entry their own Covenant proof |
| [0015](0015-bundle-statechart-plugin.md) | Accepted | Bundle Statechart as a Jido Plugin |
| [0016](0016-fsm-plugin-namespace.md) | Accepted | Give the bundled FSM Plugin one public namespace |
| [0017](0017-behavior-tree-turn-ownership.md) | Proposed | Run Behavior Trees through v3 Agent Turns |
| [0018](0018-stateless-ai-browser-tools.md) | Accepted | Use the AI Plugin for stateless browser tools |
| [0019](0019-one-owner-for-agent-state-fields.md) | Accepted | Give each Agent state field one authoritative owner |
| [0020](0020-fixed-home-instance-clustering.md) | Accepted | Configure one home per clustered Jido instance namespace |
| [0021](0021-shared-blackboard-ownership.md) | Proposed | Give each shared blackboard one owner |
| [0022](0022-durable-react-tool-results.md) | Proposed | Save completed ReAct tool results within their execution |
| [0023](0023-reuse-durable-execution-inputs.md) | Proposed | Reuse saved input in durable execution records |

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
