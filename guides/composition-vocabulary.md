# Composition Vocabulary

When one Agent declares other Agents, Jido uses a small set of terms for the
parts. This page defines each term against one example, so the other Compose
Agents guides can use them without explanation.

## One Team, Every Term

```elixir
defmodule MyApp.Worker do
  use Jido.Agent, name: "worker"

  state do
    schema(Zoi.object(%{team: Zoi.string() |> Zoi.default("none")}))
  end

  routes do
    signal_source("/my_app/worker")
    route "task.run", MyApp.RunTask
  end
end

defmodule MyApp.Team do
  use Jido.Agent, name: "team"

  state do
    schema(
      Zoi.object(%{
        name: Zoi.string() |> Zoi.default("alpha"),
        size: Zoi.integer() |> Zoi.default(2)
      })
    )
  end

  routes do
    signal_source("/my_app/team")
    route "task.done", MyApp.RecordDone
  end

  topology do
    agent :lead, MyApp.Worker

    agent :workers, MyApp.Worker do
      count state(:size)
      initial_state %{team: state(:name)}
    end

    connections do
      connect "task.done", from: :workers, to: :root
    end
  end
end

{:ok, team} = Jido.start_agent(MyApp.Team, id: "team-1")
```

That declaration and that start call produce this:

```text
DECLARATION (data)                       RUNTIME (processes)

definition MyApp.Team                    activation "team-1"
  topology                                 Agent Server "team-1"            owner
    member :lead     count 1               slot $topology/lead/1            child
    member :workers  count state(:size) -> slot $topology/workers/1         child
    connection "task.done"                 slot $topology/workers/2         child
      :workers -> :root
instance "team-1", state %{size: 2}
```

The left column is data. You can build it, inspect it, and store it without a
process. The right column exists only after `Jido.start_agent/2`.

## Declaration Terms

| Term | Meaning | In the example |
| --- | --- | --- |
| Definition | An Agent's schema, routes, Plugins, and topology. `id` and `state` are `nil`. | `MyApp.Team.definition()` |
| Instance | A definition with an `id` and validated state. | `"team-1"` with `%{name: "alpha", size: 2}` |
| Topology | The `agents` and `connections` declared inside a definition. Declaring it starts nothing. | The `topology` block |
| Member | One named entry in `topology.agents`: a definition, a count, and an initial state. | `:lead`, `:workers` |
| `:root` | The reserved name for the declaring Agent itself. | The `to:` of the connection |
| Count | Slots per member. A positive integer or a state binding. Default `1`. | `state(:size)` |
| Initial state | The state each slot starts with. Checked against the member's schema. | `%{team: state(:name)}` |
| State binding | A `state/1` reference to a field of the parent's committed state. | `state(:size)`, `state(:name)` |
| Connection | A Signal type, a source, a destination, and a delivery mode. | `"task.done"` from `:workers` to `:root` |
| Delivery | `:single` (default) or `:broadcast`. A counted member needs `:broadcast` as a destination. | `:single` |
| Bus | A local Signal bus declared with `Jido.Plugin.Bus.DSL`, used as the endpoint `bus(:name)`. | Not declared here |

A member's definition can have its own topology, so teams nest. Each level
owns its own slots and nothing below them.

## Runtime Terms

| Term | Meaning | In the example |
| --- | --- | --- |
| Activation | The supervision tree for one live Agent. It holds the Agent Server, Plugin runtimes, slots, and buses. | The tree under `"team-1"` |
| Slot | One running position of a member. Numbered from 1. Each slot is one Agent Server with its own state and revision. | `$topology/workers/2` |
| Tag | A child's key in `Jido.AgentServer.children/2`. Topology tags have the form `"$topology/<member>/<slot>"`. | `"$topology/lead/1"` |
| Member ID | The parent ID plus the tag. Stable for the life of the slot. | `"team-1/$topology/workers/2"` |
| Child | Any Agent supervised by another Agent. Slots are children. So are Agents started with the `agent_start/3` Directive. | All three slots |
| Owner | The Agent whose activation supervises a child. Owned children stop with it. | `"team-1"` |
| Placement | Where a child's activation runs. `:owned` (default) is under the owner. `:independent` is under the instance supervisor. Slots are always `:owned`. | `:owned` |
| Partition | A scope for live Agent IDs inside one Jido instance. Children run in their owner's partition. | Default partition |

Two lookups cover most needs. `Jido.AgentServer.children/2` returns every
child by tag. `Jido.AgentServer.members/3` returns the PIDs for one member
name, in slot order.

## Rules That Follow

- **State never merges.** Every slot owns its own state and revision. A
  binding reads the owner's committed state when the slot is planned. If a
  bound value changes later, the slot is replaced. The owner's Turns can't read
  or write a slot's state.
- **Connections route. They don't own.** Adding or removing a connection never
  starts or stops a process.
- **Each hop is a new Turn.** A connection delivers a cast after the sender
  commits. The receiver commits separately. There is no transaction across the
  team.
- **The owner commits structure.** A topology change is a Turn on the owner.
  A slot's work is a Turn on that slot.
- **A topology-member output without a matching connection is dropped.** The
  sender's effect still reports `:succeeded`. See
  [Connect Agent Outputs](connect-agent-outputs.livemd).

## Common Mix-Ups

| You might say | In Jido |
| --- | --- |
| "Start the workers" | Commit a topology. The Server starts the slots. |
| "The worker's PID" | The current process of one slot. Read it with `members/3`. It changes after a restart. |
| "Update the child's state" | Send the child a Signal. Its own Turn changes its state. |
| "Send to every worker" | A `:broadcast` connection, or `agent_send/2` to a counted member. |
| "Delete the worker" | Return `agent_remove/1` from a Turn, or lower a bound count. |
| "Owner process" | Two meanings. The owning Agent supervises children. A process registered with `Jido.AgentServer.attach/3` only keeps an Agent from idling out. |

## Next

- [Nested Agents](declare-agent-topology.livemd): declare members, counts, and
  bindings.
- [Connect Agent Outputs](connect-agent-outputs.livemd): route Signals between
  members.
- [Change Live Composition](change-live-composition.md): reshape a running
  team.
