# Signals and routing

Construct input with `Jido.Signal.new/3` or `new!/3`. Use a type, map data, and
source. Declare routes in the Agent definition or the Spark `routes` block.

A route target can be an Action or Flow. A `{target, defaults}` route merges
its defaults with Signal data. Signal data takes precedence. The merge is
shallow. The resulting route selection must contain exactly one executable;
zero or multiple targets return a routing error.

The `routes` block can set `signal_source` and declare nested `define` entries
for generated Signal and command functions. Exact routes can expose interfaces;
wildcards and match predicates cannot expose positional helpers.

A caller timeout does not undo active work. Remote admission uses the caller's
clock through a bounded query. Failed remote liveness checks during a partition
do not prove that the remote process died.

See the [routing example](../lib/examples/01_basic/README.md) and
[remote API tests](../test/jido/agent/remote_api_test.exs).
