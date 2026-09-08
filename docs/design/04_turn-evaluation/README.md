> Subsystem review index. This document is pending approval.

# 04 — Turn evaluation

Current comparison: [gap analysis](gap-analysis.md).

Turn evaluation owns the pure command pipeline shared by direct Agent commands
and live Agent Server execution.

Review [the Turn evaluation design](turn-evaluation.md) against
`lib/jido/agent/command/runner.ex`, `lib/jido/agent/command.ex`, and
`lib/jido/agent/turn.ex`.

Main alignment questions:

- Is route selection complete before Plugin preparation?
- Which Signal is the source Signal and which is the effective Signal?
- Can a Plugin change the selected executable?
- Which executable output is private?
- Who assembles and validates the complete candidate Agent?
- Do direct and live evaluation produce the same candidate and Directives?
