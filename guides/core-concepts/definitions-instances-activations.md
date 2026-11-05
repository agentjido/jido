# Definitions and Runtime

Jido separates what an Agent is from where it runs. This guide names each layer, shows what each one owns, and explains which layers survive a restart.

## The layers

| Layer | What it is | How you get one | Lives until |
| --- | --- | --- | --- |
| Agent definition | Data: schema, routes, Plugins, topology. It has no ID and no state. | `use Jido.Agent` or `Jido.Agent.define!/1` | You change it |
| Agent instance | A definition plus an ID and complete state. It is still only a value. | `Jido.Agent.instantiate!/2` | No one refers to it |
| Jido instance | A supervisor that hosts live Agents and the services they use. | `use Jido` or `Jido.start/1` | You stop it |
| Activation | A supervisor for one live Agent and the processes tied to it. | `Jido.start_agent/3` | The Agent stops |
| AgentServer | The worker process in an activation. It runs Turns and holds the committed Agent. | The return value of `Jido.start_agent/3` | The next crash or stop |
| Turn | One evaluation of one Signal. | A `Jido.AgentServer.call/3` or a `Jido.Agent.cmd/3` | It ends |

"Instance" has two meanings here. An **Agent instance** is a data value. A **Jido instance** is a supervisor. Other guides say "the instance" when the context makes the meaning clear, and this guide always uses the full name.

## From definition to value

A definition holds nil `id` and `state`. An Agent module compiles to one, and a Map can build the same kind of value.

```elixir
defmodule LayersGuide.AddTicket do
  use Jido.Action,
    name: "layers_guide_add_ticket",
    schema: Jido.Joi.object(%{subject: Jido.Joi.string()})

  @impl Jido.Action
  def run(%{subject: subject}, %{agent_state: state}) do
    {:ok, %{state | open: [subject | state.open]}}
  end
end

defmodule LayersGuide.Queue do
  use Jido.Agent, name: "ticket_queue"

  state do
    schema Jido.Joi.object(%{open: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([])})
  end

  routes do
    signal_source "/support/queue"
    route "ticket.add", LayersGuide.AddTicket, as: :add
  end
end

definition = Jido.Agent.definition(LayersGuide.Queue)

%Jido.Agent{id: nil, state: nil, name: "ticket_queue"} = definition
true = Jido.Agent.definition?(definition)

first = LayersGuide.Queue.instantiate!(id: "queue-a")
second = LayersGuide.Queue.instantiate!(id: "queue-b", state: %{open: ["Printer jam"]})

{%{open: []}, %{open: ["Printer jam"]}} = {first.state, second.state}
true = Jido.Agent.instance?(first)
```

Nothing has started yet. Building these values starts no process and runs no handler. Each value carries its own copy of the definition data, and a Turn returns a new value. See [Define an Agent](../agents/define-and-instantiate-an-agent.livemd).

The copy matters later. Mutation Directives change the definition data inside one Agent instance, which can make it differ from its module. `Jido.Agent.definition/1` applied to that value returns its current data. See [Mutations and Diffs](../agents/agent-mutations-and-diffs.livemd).

Actions and Flows follow the same split. An Action module or a `Jido.Flow` value is a definition. A `Jido.Instruction` binds one to params and context. Running it creates an execution that ends when the work does. See [Instructions and Targets](../actions/instructions.md).

## From value to process

A Jido instance is the host. Start one for each isolated set of Agents. It has its own Runner, task supervisor, and registry, and it can set a default store and AgentServer options. See [Instances and Tenants](../operations/configuration-and-tenant-isolation.md).

`Jido.start_agent/3` creates an Agent instance from the module and options, or takes one you already built. It then starts an activation for it.

```elixir
{:ok, _host} = Jido.start(name: LayersGuide.Jido)

{:ok, server} = Jido.start_agent(LayersGuide.Jido, LayersGuide.Queue, id: "queue-a")
:ok = Jido.AgentServer.await_ready(server)

activation = Jido.AgentServer.activation(server)
true = activation != server

# A value you built keeps its ID and state.
{:ok, seeded} = Jido.start_agent(LayersGuide.Jido, second)
%{open: ["Printer jam"]} = Jido.AgentServer.agent(seeded).state
```

The server takes a copy of the value. Later Turns change the server's Agent, and your variable stays as it was.

```elixir
{:ok, _committed, []} =
  Jido.AgentServer.call(server, LayersGuide.Queue.add_signal!(%{subject: "Refund"}))

%{open: []} = first.state
%{agent: %{state: %{open: ["Refund"]}}, state_version: 1} = Jido.AgentServer.snapshot(server)
```

One definition can back many live Agents. The ID must be unique within a Jido instance and partition, and the same ID can repeat across either boundary.

```elixir
{:ok, _other_host} = Jido.start(name: LayersGuide.OtherJido)

{:error, {:already_started, ^server}} =
  Jido.start_agent(LayersGuide.Jido, LayersGuide.Queue, id: "queue-a")

{:ok, tenant_copy} =
  Jido.start_agent(LayersGuide.Jido, LayersGuide.Queue, id: "queue-a", partition: "acme")

{:ok, other_host_copy} = Jido.start_agent(LayersGuide.OtherJido, LayersGuide.Queue, id: "queue-a")

3 = length(Enum.uniq([server, tenant_copy, other_host_copy]))
```

## Why an activation sits above the worker

The AgentServer worker can crash and restart. An activation is the part that stays. It owns these things across a worker restart:

- the last committed Agent and revision, in a local checkpoint
- the Agent's Plugin runtimes and topology buses, which restart with the worker
- its relationship to a parent Agent and to independent children
- attached owners, and whether admission is closed

The worker's PID therefore changes on a restart, and the activation's PID does not. `Jido.AgentServer.activation/1` returns the activation. A parent's link to its child is to the activation, so it outlasts a worker restart. See [Agent Lifecycle](../agent-servers/agent-activation-control.md).

A bare worker from `Jido.AgentServer.start_link/1` has no activation, and it rejects topology, persistence, and runtime Plugins. Prefer `Jido.start_agent/3`. See [Agent Lifecycle](../agent-servers/agent-activation-control.md#run-a-bare-worker).

## A durable Agent outlives its processes

Without a store, the Agent ends with its activation. With a store, the logical Agent continues with no process at all. Its identity is a `Jido.Agent.Ref`, the exact `{namespace, partition, id}` tuple, and no PID is part of that. An Agent can run on one activation today and on a new one tomorrow.

```elixir
{:ok, _durable_host} =
  Jido.start(
    name: LayersGuide.DurableJido,
    namespace: "guides/support",
    persistence: {Jido.Persistence.ETS, table: :layers_guide}
  )

{:ok, durable} =
  Jido.start_agent(LayersGuide.DurableJido, LayersGuide.Queue, id: "queue-d", persistence: :inherit)

:ok = Jido.AgentServer.await_ready(durable)
first_activation = Jido.AgentServer.activation(durable)

{:ok, _committed, []} =
  Jido.AgentServer.call(durable, LayersGuide.Queue.add_signal!(%{subject: "Lost parcel"}))

# Save and stop. No process remains.
:ok = Jido.hibernate(LayersGuide.DurableJido, durable)
nil = Jido.whereis_agent(LayersGuide.DurableJido, "queue-d")

# The same logical Agent starts on a new activation.
{:ok, thawed} = Jido.thaw(LayersGuide.DurableJido, LayersGuide.Queue, "queue-d")
:ok = Jido.AgentServer.await_ready(thawed)

true = Jido.AgentServer.activation(thawed) != first_activation
%{agent: %{state: %{open: ["Lost parcel"]}}, state_version: 1} = Jido.AgentServer.snapshot(thawed)
```

The thawed Agent uses the definition in its save. Changing the module does not change a saved Agent until you upgrade it. See [Upgrade Live Agents](../agent-servers/upgrade-live-agents.md).

## What survives what

| Event | Worker PID | Activation PID | Committed Agent | Queue and Turn in progress |
| --- | --- | --- | --- | --- |
| Turn fails | Same | Same | Unchanged | The next Turn runs |
| Worker crashes | New | Same | Restored from the checkpoint or store | Lost, except that a durable Flow resumes |
| Activation stops, no store | Gone | Gone | Gone | Lost |
| Activation stops, with a store | Gone | Gone | Saved. Reloaded at the next start | Lost, except that a durable Flow resumes |
| Jido instance stops | Gone | Gone | As in the two rows above | As in the two rows above |

The saved Agent lasts as long as the store does. The ETS adapter in the example loses its data when the BEAM stops. See [Durability Model](../durability/durability-model.md).

## Related

- [OTP Concepts for Jido](otp-concepts-for-jido.md) covers the supervisors and their settings.
- [Start and Address Agents](../agent-servers/start-and-address-live-agents.livemd) shows lookups, partitions, and Refs.
- [Hibernate and Thaw](../agent-servers/hibernate-thaw-and-activate.md) covers moving an Agent in and out of memory.
