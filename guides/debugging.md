# Inspect a live Agent

Use `AgentServer.agent/1`, `snapshot/1`, and `status/1`. The status shows the phase,
active Turn, postponed count, mailbox count, and runtime lifecycle controls.
Use `children/1` for ownership. The old Server State shape is not a public contract.

Enable bounded history with `set_debug/2` and read `recent_events/2`. Use safe
error projections for external reports. Keep one failed run's source hash,
command, runtime, and complete assertions when investigating timing failures.

See [observability](observability.md) and [testing](testing.md).
