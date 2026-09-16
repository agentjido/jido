# Signals and routing

Construct input with `Jido.Signal.new/3` or `new!/3`. Use a type, map data, and
source. Declare routes in the Agent definition or the declarative `routes` block.

A route target can be an Action or Flow. A `{target, defaults}` route merges
its defaults with Signal data. Signal data takes precedence. The merge is
shallow. Jido selects the first target in Jido Signal Router order. No match
returns a routing error.

Action Exec context includes Server-owned `:agent_id`, `:agent_state`,
`:signal`, and `:plugin_inputs`. In a live Turn, AgentServer also sets `:jido`
and `:partition` from its own state, even when the caller supplies other
values. Direct `Agent.cmd/3` has no Server state; it passes caller values for
those two keys and leaves them absent when the caller does not supply them.

The `routes` block can set `signal_source` and declare nested `define` entries
for generated Signal and command functions. Exact routes can expose interfaces;
wildcards and match predicates cannot expose positional helpers.

A caller timeout does not undo active work. Remote admission uses the caller's
clock through a bounded query. Failed remote liveness checks during a partition
do not prove that the remote process died.

See the [routing example](https://github.com/agentjido/jido/blob/release/v3/examples/01_basic/README.md) and
[remote API tests](../test/jido/agent_server/remote_api_test.exs).
