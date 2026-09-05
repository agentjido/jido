# Bus Delivery

Feature ID: `04_03_bus_delivery`. Status: implemented within the tested scope.

## Added feature

A real Bus Client delivers ordered records, retries failed Turns, and acknowledges after commit. Read this after the Basic and Workflow groups.

## Use

```elixir
alias Jido.Examples.BusDelivery

alias Jido.Signal.Bus
{:ok, bus} = Bus.start_link(name: :example_commands, jido: jido)
{:ok, _server} = Jido.start_agent(jido, BusDelivery)
Bus.publish(bus, [BusDelivery.record_signal!(3)])
```

## Evidence

4 enabled tests:

- durable delivery waits for a commit before it sends the next record.
- a failed Turn retries the same record before later input.
- a restarted Client resumes the subscription and duplicate IDs keep one value.
- normal input outside the subscription path does not enter the Agent.

Run:

```shell
mix test --include integration test/examples/04_runtime/04_03_bus_delivery --seed 0
```

[Source](../../../../lib/examples/04_runtime/04_03_bus_delivery/bus_delivery.ex) ·
[Tests](../../../../test/examples/04_runtime/04_03_bus_delivery/bus_delivery_test.exs)

## Boundary and next question

The Bus retains records in local memory. This does not prove recovery after a node loss. Use one durable subscription ID per logical consumer.

See the [gap register](../../runtime-multi-agent-gaps.md) and
[verification report](../../runtime-multi-agent-results.md).
