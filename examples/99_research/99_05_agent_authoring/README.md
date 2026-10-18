# Composable Agent authoring

This research example shows how a Spark DSL produces one canonical `%Jido.Agent{}`.
`Jido.Agent` remains the public runtime API. It implements the authoring
contract in [the specification](../../../AGENT_AUTHORING_SPEC.md).

Read [the team](example.ex), then [Alice](alice.ex). The team has named and inline
Actions, transforms, input helpers, emission contracts, members, connections,
schedules and a local Signal bus declaration. Alice uses the same
input and emission boundary without a topology.

Run from the `jido` package:

```sh
mix run --no-start examples/99_research/99_05_agent_authoring/demo.exs
mix test test/authoring/agents/composable_agent_test.exs test/authoring/agents/composable_extensions_test.exs --include authoring --seed 0
```

The script prints canonical Agent structs and checks that struct validation preserves
every field. It also checks exact JSON round trips with a temporary local
reference Registry. It runs no Action, Flow, model, timer, bus, or Agent process. No
credentials or cleanup are required. Invalid definitions fail validation.

Routes select one input handler in declaration order. A bare route passes its
Signal through. A transform produces one output Signal. An Action consumes its
input and declares emissions explicitly. `emits` constrains possible output
types; it does not create output. Connections select recipients for outputs.

Topology contains immediate agents and connections. Counted members use the
same Agent boundary. `state/1` records a copied initial input. It does not create
shared state or track later changes. Signal bus connections declare publication
and subscription; member definitions need no bus configuration.

The reference providers are [Scheduling](../../../lib/jido/plugin/scheduler/dsl.ex),
and
[Signal Bus](../../../lib/jido/plugin/bus/dsl.ex). Extensions and
Plugins use the same contribution format. Plugin-owned DSL in source files does
not depend on the position of the Plugin declaration. For generated modules
without a source file, select providers with `extensions:`.

Evidence: [core authoring tests](../../../test/authoring/agents/composable_agent_test.exs)
and [provider tests](../../../test/authoring/agents/composable_extensions_test.exs).
These tests prove authoring and normalization. JSON round-trip tests are in
`test/authoring/agents/json_test.exs`. Process activation,
message delivery, Action execution, scheduling, and model calls remain outside
this authoring example. Runtime composition needs a separate implementation
and contract.

Definitions and instances use the same struct. Only `id` and `state` differ.
The old topology activation graph does not implement these output connections.
Activation rejects nonempty logical topologies until that runtime contract is implemented.
