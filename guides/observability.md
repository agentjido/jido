# Observe execution

`Jido.Telemetry` is the one V3 runtime observation contract. It covers Agent
lifecycle, Turn result, commit, Directive work, settlement, admission
rejection, persistence, and static local Topology operations.

Use the committed revision and terminal Outcome to distinguish a failed
command from a failure after commit. A successful Turn span ends at the live
commit. The separate settlement fact can occur later.

Use `Jido.Error.to_map/1` at a transport boundary. It omits stacktraces,
redacts sensitive fields, limits depth and collection size, and keeps bounded
validation paths. Invalid UTF-8 binaries use bounded inspection. Do not add
raw Agent state, including Plugin-owned fields, secrets, or arbitrary exception values to
public metadata.

Every semantic event has `schema_version: 1`. Namespaced Agent events project
`agent_namespace`, `agent_partition`, and `agent_id`. Default metric tags do
not use these identity fields. A registered Jido failure can include a bounded
`error_code`, but never the raw error or its message.

`AgentServer.status/1` gives queue and execution status. Enable bounded debug
history with `set_debug/2` and read `recent_events/2` when needed. Observation
must not change the command result. Direct execution does not prove a live
commit, even when executable spans exist.

Jido can map semantic events to OpenTelemetry when the host adds
`opentelemetry_api` and an SDK. The dependency is optional. The host owns SDK
startup, sampling, export, and vendor configuration.

See the [runtime observation tests](../test/jido/agent_server/runtime_observability_test.exs),
the [OpenTelemetry contract tests](../test/jido/telemetry/open_telemetry_test.exs),
and the [causal trace checks](../test/examples/04_runtime/04_08_causal_trace/causal_trace_test.exs).
Run the
[semantic boundary demonstration](../examples/04_runtime/04_07_agent_observation/semantic_boundaries.exs)
to see Agent, persistence, and local Topology facts together.
