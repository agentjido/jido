> Subsystem review index. This document is pending approval.

# 06 — Commit and effects

Current comparison: [gap analysis](gap-analysis.md).

This subsystem defines the boundary between a candidate Agent, committed live
state, caller results, transient Directives, and explicitly recoverable work.

Documents:

- [Commit and effects](commit-and-effects.md)
- [Durability guarantee](durability-guarantee.md)

Main alignment questions:

- What exact operation makes candidate state live?
- What does a successful command confirm?
- When can Directive work start?
- Which failures can undo state and which cannot?
- How does durable work intent commit with the business change?
- Which delivery and duplicate rules belong to a capability instead of core?
