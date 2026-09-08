> Subsystem review index. This document is pending approval.

# 90 — Package and extension boundaries

Current comparison: [gap analysis](gap-analysis.md).

This area decides which contracts belong in Jido core and which belong in
durable, cluster, transport, AI, or application packages.

Review [the runtime extension boundaries](runtime-extension-boundaries.md).

A package needs a new core contract when it must read private Server state,
send private Server messages, construct generated runtime names, bypass the
Turn candidate boundary, dispatch work before commit, or treat a PID as
durable identity.
