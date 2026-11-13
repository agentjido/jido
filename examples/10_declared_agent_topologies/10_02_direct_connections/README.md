# 10_02 Direct Connections

Explicit outputs form a local root → worker → sink → root pipeline.

## What you will learn

- How an explicit forward sends the request to a named Agent.
- How connections route new outputs between named Agents.
- How a transform creates a receipt Signal without an Action.

## Read the code

Read [the Agent](direct_connections.ex), then [the behavior tests](direct_connections_test.exs).
The [worker](worker.ex) commits work and emits completion. The [sink](sink.ex)
transforms completion into a receipt. Tests observe all runtimes through
`Jido.list_agents/2` and public AgentServer snapshots.

## Run it

```sh
mix test.examples examples/10_declared_agent_topologies/10_02_direct_connections --warnings-as-errors
```

Expected result: the request commits at the root, the worker doubles its value, the sink transforms completion into a receipt, and the root commits the receipt. An incompatible destination is rejected. Owner shutdown stops all runtimes.

## Important behavior

```elixir
connections do
  connect "examples.topology.pipeline.completed", from: :worker, to: :sink
  connect "examples.topology.pipeline.receipt", from: :sink, to: :root
end
```

The root uses a route body with `forward to: agent(:worker)`.
An Action emits with `Jido.Agent.Directive.emit/1`. A transform route returns
`{:ok, signal}` or an error. Accepting input in an ordinary Action does not
automatically emit output.

Routes select the first matching handler. Connections select all matching
edges for the logical source and output type. Use distinct request and result
types to avoid an unintended cycle. Jido checks that destinations accept the
Signal type. Output production remains `:unchecked`.

## Limits

The root call confirms its own commit. Every destination commits a separate
Turn. Delivery uses best-effort casts; there is no pipeline transaction or
durable acknowledgement. Use the Bus lesson for counted broadcast.

## Files

- [Root Agent](direct_connections.ex)
- [Worker](worker.ex)
- [Sink](sink.ex)
- [Tests](direct_connections_test.exs)

Previous: [Named Agents](../10_01_named_agents/README.md) | Next: [Local Bus Broadcast](../10_03_bus_broadcast/README.md)
