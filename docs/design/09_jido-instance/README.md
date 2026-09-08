> Subsystem review index. This document is pending approval.

# 09 — Jido instance

Current comparison: [gap analysis](gap-analysis.md).

A Jido instance owns one local runtime, its supervision tree, configuration,
Registry, task supervision, Agent lifecycle pool, and application-facing API.

Review [the Jido instance design](jido-instance.md) against `lib/jido.ex` and
`lib/jido/application.ex`.

[The instance callback analysis](instance-callbacks.md) limits callbacks to
instance-owned policy. It proposes an optional configuration normalization
callback as the first useful contract. It keeps lifecycle observation in
Telemetry and keeps Agent behavior in Plugins and Directives.

Main alignment questions:

- Is the instance module the stable namespace and public runtime facade?
- Which configuration is required and how is it validated?
- What supervision strategy and child order express runtime dependencies?
- Does the facade use Agent Ref, PID, or both during migration?
- How are multiple instances isolated?
- Which persistence boundary is configured by the instance?
