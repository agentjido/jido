# Observe execution

`Jido.Observe` supplies spans, safe error metadata, and tracer integration.
The live Agent events cover lifecycle, admission, execution, commit, and directive
work. Use the committed revision and terminal outcome to distinguish a failed
command from a failure after commit. Update old event consumers to the V3 fields.

Use `Jido.Error.to_map/1` at a transport boundary. It omits stacktraces, redacts
sensitive fields, limits depth and collection size, and keeps bounded validation
paths. Invalid UTF-8 binaries use bounded inspection. Do not add raw Agent state,
Plugin state, secrets, or arbitrary exception values to public metadata.

`AgentServer.status/1` gives queue and execution status. Enable bounded debug
history with `set_debug/2` and read `recent_events/2` when needed.
Observation must not change the command result. Direct execution does not prove a
live commit, even when executable spans exist.

See [Agent lifecycle events](../test/jido/observe/agent_lifecycle_test.exs) and
[causal trace checks](../test/jido/observe/causal_trace_test.exs).
