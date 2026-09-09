# Observe execution

`Jido.Telemetry` supplies the version-1 semantic event contract. It covers
Agent lifecycle, Turn result, commit, Directive work, settlement, admission
rejection, persistence, and static local Topology operations. Use the committed
revision and terminal Outcome to distinguish a failed command from a failure
after commit. `Jido.Observe` remains as a compatible tracing facade.

Use `Jido.Error.to_map/1` at a transport boundary. It omits stacktraces, redacts
sensitive fields, limits depth and collection size, and keeps bounded validation
paths. Invalid UTF-8 binaries use bounded inspection. Do not add raw Agent state,
Plugin state, secrets, or arbitrary exception values to public metadata.

Every semantic event has `schema_version: 1`. Namespaced Agent events project
`agent_namespace`, `agent_partition`, and `agent_id`. Default metric tags do not
use these identity fields. A registered Jido failure can include a bounded
`error_code`, but never the raw error or its message.

`AgentServer.status/1` gives queue and execution status. Enable bounded debug
history with `set_debug/2` and read `recent_events/2` when needed. Observation
must not change the command result. Direct execution does not prove a live
commit, even when executable spans exist.

See [Agent lifecycle events](../test/jido/observe/agent_lifecycle_test.exs) and
[causal trace checks](../test/jido/observe/causal_trace_test.exs). Run the
[semantic boundary demonstration](../examples/04_runtime/04_09_agent_observation/semantic_boundaries.exs)
to see Agent, persistence, and local Topology facts together.
