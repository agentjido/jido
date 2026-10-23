# 07_11 Direct Connections

Explicit outputs form a local root → worker → sink → root pipeline.

## What you will learn

- How an explicit forward sends the request to a named Agent.
- How connections route new outputs between named Agents.
- How a transform creates a receipt Signal without an Action.

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
  connect "examples.topology.pipeline.completed", from: :worker, to: :sink
  connect "examples.topology.pipeline.receipt", from: :sink, to: :root
end
```

The root uses `forward "examples.topology.pipeline.request", to: agent(:worker)`.
An Action emits with `Jido.Agent.Directive.emit/1`. A transform route returns
`{:ok, signal}` or an error. Accepting input in an ordinary Action does not
automatically emit output.

Routes select the first matching handler. Connections select all matching
edges for the logical source and output type. Use distinct request and result
types to avoid an unintended cycle. Jido checks that destinations accept the
Signal type. Output production remains `:unchecked`.

The root call confirms its own commit. Every destination commits a separate
Turn. Delivery uses best-effort casts; there is no pipeline transaction or
durable acknowledgement. Use the Bus lesson for counted broadcast.

Previous: [Named Agents](../07_01_independent/README.md) | Next: [Local Bus Broadcast](../07_03_bus_swarm/README.md)
