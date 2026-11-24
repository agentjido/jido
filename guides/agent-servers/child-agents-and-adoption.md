# Start and Transfer Child Agents

Start an Agent from application code when its lifetime depends on a request. Give the Agent an ID that your application can use to find it again.

A runtime start creates a standalone Agent under the Jido instance. Your application can assign work to this Agent, read its state, and assign it a runtime owner. If an Agent must own a fixed set of members, use [Declare Agent Topology](../composition/declare-agent-topology.livemd).

## Start and observe a courier

This example uses a delivery request ID as the courier's Agent ID. The partition limits registry lookups to this dispatch group.

```elixir
defmodule CourierGuide.Courier do
  use Jido.Agent, name: "delivery_courier"

  state do
    schema Jido.Joi.object(%{delivered: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/couriers"

    route "parcel.deliver", as: :deliver do
      action %{count: count},
        schema: Jido.Joi.object(%{count: Jido.Joi.integer()}),
        context: context do
        {:ok, %{context.agent_state | delivered: context.agent_state.delivered + count}}
      end
    end
  end
end

instance = CourierGuide.Jido
scope = [partition: "north-dispatch"]
id = "delivery-42"

{:ok, _instance} = Jido.start(name: instance, namespace: "guides/couriers")
{:ok, courier} = Jido.start_agent(instance, CourierGuide.Courier, [id: id] ++ scope)
:ok = Jido.AgentServer.await_ready(courier)

^courier = Jido.whereis_agent(instance, id, scope)
[{^id, ^courier}] = Jido.list_agents(instance, scope)

{:ok, signal} = CourierGuide.Courier.deliver_signal(%{count: 3})
{:ok, %{status: :committed}} = Jido.AgentServer.call(courier, signal)
%{agent: %{state: %{delivered: 3}}} = Jido.AgentServer.snapshot(courier)
```

Keep the ID and partition in application data. Look up the current PID when you need a local handle. See [Start and Address Agents](start-and-address-live-agents.livemd) for Address-based calls.

## Adopt and transfer the courier

Start both dispatch Agents in the courier's instance and partition. Use `Jido.transfer_agent_ownership/4` with `expected: nil` for the first adoption. To transfer ownership again, pass the current ownership value. Give each operation its own request ID.

```elixir
defmodule CourierGuide.Dispatch do
  use Jido.Agent, name: "courier_dispatch"
end

{:ok, north} = Jido.start_agent(instance, CourierGuide.Dispatch, [id: "north"] ++ scope)
{:ok, south} = Jido.start_agent(instance, CourierGuide.Dispatch, [id: "south"] ++ scope)
:ok = Jido.AgentServer.await_ready(north)
:ok = Jido.AgentServer.await_ready(south)

{:ok, courier_address} = Jido.agent_address(instance, id, scope)
{:ok, north_address} = Jido.agent_address(instance, "north", scope)
{:ok, south_address} = Jido.agent_address(instance, "south", scope)

{:ok, nil} = Jido.agent_ownership(instance, courier_address)

{:ok, adopted} =
  Jido.transfer_agent_ownership(instance, courier_address, north_address,
    expected: nil,
    request_id: "adopt-delivery-42"
  )

{:ok, transferred} =
  Jido.transfer_agent_ownership(instance, courier_address, south_address,
    expected: adopted,
    request_id: "move-delivery-42"
  )

%{owner_address: ^south_address} = transferred
{:ok, ^transferred} = Jido.agent_ownership(instance, courier_address)
```

The child keeps its state and worker through the transfer. The current owner's activation controls its lifetime. Ownership is local to these activations.

```elixir
:ok = Jido.stop_agent(instance, north, scope)
^courier = Jido.whereis_agent(instance, id, scope)
%{agent: %{state: %{delivered: 3}}} = Jido.AgentServer.snapshot(courier)

ref = Process.monitor(courier)
:ok = Jido.stop_agent(instance, south, scope)

receive do
  {:DOWN, ^ref, :process, ^courier, _reason} -> :ok
after
  5_000 -> raise "the courier did not stop"
end
```

To stop a request-scoped Agent directly, call `Jido.stop_agent/3` with its ID and partition. For the lifetime of a declared member, see [Parent and Child Agents](../composition/parent-and-child-agents.md).
