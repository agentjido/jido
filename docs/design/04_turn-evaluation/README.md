# 04 — Turn evaluation

## Briefing

Jido uses one private Runner for direct and live candidate evaluation. It
selects a Turn from the unchanged source Signal, executes the selected Action
or Flow, passes the result through the one-phase Agent Plugin pipeline, and
validates one candidate Agent.

```text
source Signal
  -> pure Plugin preparation
  -> live Plugin admission (Server only)
  -> fixed Turn selection
  -> executable input
  -> Jido.Exec
  -> protect Plugin-owned fields
  -> validate each Directive once
  -> reduce Plugin-owned fields
  -> validate candidate Agent
```

Agent Plugins can reject or return one portable package-owned prepared input.
Live Agent Server Plugins can reject or return only their own transient runtime
input. No Plugin can change the Signal, caller context, Agent, route, prepared
input, or another package's input. The Runner selects the executable from the
unchanged source Signal.

## Boundary

This seam owns selection, executable-result normalization, candidate assembly,
and direct/live candidate parity. It does not own live admission, tasks,
timeouts, persistence, commit, or post-commit Directive handling.

The public entry point is `Jido.Agent.cmd/3`. `Jido.Agent.Turn` remains the
public value returned by custom `handle_signal/2` callbacks. The Runner and
Agent Plugin pipeline remain private. Direct evaluation does not create a
`Jido.Agent.Command`; that value belongs to live Agent Server admission.

`Jido.Agent.Turn.Outcome` is a terminal record produced by the Agent Server.
It is not an authoring value and has no public constructor or schema.

## Documents

- [Design](design.md)
- [Alignment](alignment.md)
