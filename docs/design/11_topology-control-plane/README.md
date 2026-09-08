> Subsystem review index. This document is pending approval.

# 11 — Topology control plane

Current comparison: [gap analysis](gap-analysis.md).

The Topology control plane owns static definitions, validated instances, plans,
the Controller, desired state, readiness, repair, and future live target
changes. It is separate from the OTP runtime topology.

Review [Topology as one Agent authoring host](topology-authoring-host.md)
against the modules under `lib/jido/topology`.

Main alignment questions:

- Is Topology only a static startup plan or durable desired state?
- Is one owner Agent the authority for a live Topology?
- When do child processes start relative to the owner commit?
- Can reconciliation replace a target while it retains unchanged members?
- How do repair, upgrade, rolling update, and rollback differ?
