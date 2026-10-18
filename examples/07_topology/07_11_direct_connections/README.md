# 07_11 Direct Connections

Explicit outputs form a local root → worker → sink → root pipeline.

## What you will learn

- How connections route outputs between named Agents.
- How pass-through and transform routes emit Signals without an Action.
- How `emits` and destination routes permit exact connection checks.

## Read the code

Read [the Agent](direct_connections.ex), then [the behavior tests](../../../test/examples/07_topology/07_11_direct_connections/direct_connections_test.exs).
The [worker](worker.ex) commits work and emits completion. The [sink](sink.ex) transforms completion into a receipt. Tests use the [shared runtime assertions](../../../test/examples/support/agent_topology_assertions.ex).

## Run it

```sh
mix test test/examples/07_topology/07_11_direct_connections --include example --seed 0
```

Expected result: the request commits at the root, the worker doubles its value, the sink transforms completion into a receipt, and the root commits the receipt. An incompatible destination is rejected. Owner shutdown stops all runtimes.

## Important behavior and limits

```elixir
connections do
  connect "examples.topology.pipeline.request", from: :root, to: :worker
  connect "examples.topology.pipeline.completed", from: :worker, to: :sink
  connect "examples.topology.pipeline.receipt", from: :sink, to: :root
end
```

An Action emits with `Jido.Agent.Directive.emit/1`. A pass-through route emits
the unchanged Signal. A transform route returns `{:ok, signal}` or an error.
Accepting input in an ordinary Action does not automatically emit output.

Routes select the first matching handler. Connections select all matching
edges for the logical source and output type. Use distinct request and result
types to avoid an unintended cycle. Exact contracts can be `:compatible`;
wildcards or unknown output contracts can remain `:unchecked`. This is not a
proof that every runtime payload is accepted.

The root call confirms its own commit. Every destination commits a separate
Turn. Delivery uses best-effort casts; there is no pipeline transaction or
durable acknowledgement. Use the Bus lesson for counted broadcast.

Previous: [Named Agents](../07_01_independent/README.md) | Next: [Local Bus Broadcast](../07_03_bus_swarm/README.md)
