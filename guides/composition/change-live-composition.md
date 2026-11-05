# Change Live Composition

Use this guide to add, resize, replace, or remove members and to redirect connections while an Agent runs. A Turn returns mutation Directives, and AgentServer validates, commits, and applies them.

To edit a definition without a process, see [Mutations and Diffs](../agents/agent-mutations-and-diffs.livemd). This guide covers the live path.

## Return mutations from an Action

An Action returns the complete next state and a list of Directives from `Jido.Agent.Directive`. This desk has one auditor and routes for each kind of change.

```elixir
defmodule LiveGuide.Packer do
  use Jido.Agent, name: "live_packer"

  state do
    schema Jido.Joi.object(%{
             station: Jido.Joi.string() |> Jido.Joi.default("floor"),
             packed: Jido.Joi.integer() |> Jido.Joi.default(0)
           })
  end

  routes do
    signal_source "/orders/packer"

    route "order.pack", as: :pack do
      action %{items: items},
        schema: Jido.Joi.object(%{items: Jido.Joi.integer()}),
        context: context do
        {:ok, %{context.agent_state | packed: context.agent_state.packed + items}}
      end
    end
  end
end

defmodule LiveGuide.Desk do
  use Jido.Agent, name: "live_desk"

  alias Jido.Agent.Directive, as: D
  alias Jido.Agent.Topology
  alias Jido.AgentServer.Directive, as: RuntimeDirective
  alias LiveGuide.Packer

  state do
    schema Jido.Joi.object(%{packer_count: Jido.Joi.integer() |> Jido.Joi.default(2)})
  end

  routes do
    signal_source "/orders/desk"

    route "desk.packers.add", as: :add_packers do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        {:ok, context.agent_state, [D.agent_add(:packers, Packer, count: Topology.state(:packer_count))]}
      end
    end

    route "desk.packers.staff", as: :staff_packers do
      action %{count: count},
        schema: Jido.Joi.object(%{count: Jido.Joi.integer()}),
        context: context do
        {:ok, %{context.agent_state | packer_count: count}}
      end
    end

    route "desk.packers.fix", as: :fix_packers do
      action %{count: count},
        schema: Jido.Joi.object(%{count: Jido.Joi.integer()}),
        context: context do
        {:ok, context.agent_state, [D.agent_update(:packers, %{count: count})]}
      end
    end

    route "desk.auditor.replace", as: :replace_auditor do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        {:ok, context.agent_state, [D.agent_replace(:auditor, Packer, initial_state: %{station: "recount"})]}
      end
    end

    route "desk.packers.remove", as: :remove_packers do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        {:ok, context.agent_state, [D.agent_remove(:packers)]}
      end
    end

    route "desk.redirect", as: :redirect do
      action %{items: items},
        schema: Jido.Joi.object(%{items: Jido.Joi.integer()}),
        context: context do
        {:ok, work} = Packer.pack_signal(%{items: items})

        {:ok, context.agent_state,
         [
           D.connection_remove("order.pack", from: :root, to: :auditor),
           D.connection_add("order.pack", from: :root, to: :backup),
           D.emit(work)
         ]}
      end
    end

    route "desk.stop_member", as: :stop_member do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        {:ok, context.agent_state, [RuntimeDirective.agent_stop(:auditor)]}
      end
    end

    route "order.pack", as: :pack do
      transform signal do
        {:ok, signal}
      end
    end
  end

  topology do
    agent :auditor, Packer do
      initial_state %{station: "audit"}
    end

    agent :backup, Packer do
      initial_state %{station: "backup"}
    end

    connections do
      connect "order.pack", from: :root, to: :auditor
    end
  end
end
```

## Wait for readiness after each change

The reply to `Jido.AgentServer.call/3` confirms the commit and arrives before the member processes change. Call `Jido.AgentServer.await_ready/2` before you read or use members. A later Signal waits its turn, because the Agent finishes the change before it starts another Turn.

```elixir
wait_until = fn check ->
  Enum.find(1..200, fn _attempt ->
    check.() || (Process.sleep(10) && false)
  end) != nil
end

{:ok, _instance} = Jido.start(name: LiveGuide.Jido)
{:ok, desk} = Jido.start_agent(LiveGuide.Jido, LiveGuide.Desk, id: "desk-1")
:ok = Jido.AgentServer.await_ready(desk)

{:ok, add} = LiveGuide.Desk.add_packers_signal()
{:ok, accepted, _directives} = Jido.AgentServer.call(desk, add)
:ok = Jido.AgentServer.await_ready(desk)

[:auditor, :backup, :packers] = Enum.map(accepted.topology.agents, & &1.name)
[first, second] = Jido.AgentServer.members(desk, :packers)
```

## Resize a group

When a member's count refers to a state field, a state-only Turn resizes the group. Existing slots keep their process and state. Growing adds slots at the end, and shrinking stops the highest slots.

```elixir
{:ok, pack} = LiveGuide.Packer.pack_signal(%{items: 5})
{:ok, _committed, []} = Jido.AgentServer.call(first, pack)

{:ok, staff} = LiveGuide.Desk.staff_packers_signal(%{count: 3})
{:ok, _committed, []} = Jido.AgentServer.call(desk, staff)
:ok = Jido.AgentServer.await_ready(desk)

[^first, ^second, third] = Jido.AgentServer.members(desk, :packers)
5 = Jido.AgentServer.agent(first).state.packed
0 = Jido.AgentServer.agent(third).state.packed
```

`Jido.Agent.Directive.agent_update/2` replaces the declared count, which also removes the state reference. After this Turn, `packer_count` no longer controls the group.

```elixir
{:ok, fix} = LiveGuide.Desk.fix_packers_signal(%{count: 1})
{:ok, accepted, _directives} = Jido.AgentServer.call(desk, fix)
:ok = Jido.AgentServer.await_ready(desk)

[^first] = Jido.AgentServer.members(desk, :packers)
1 = Enum.find(accepted.topology.agents, &(&1.name == :packers)).count
false = Process.alive?(second)
```

## Replace or remove a member

A replacement stops the member's slots and starts new ones from the new `initial_state`. Jido does not copy the old state. Other members keep running.

```elixir
[old_auditor] = Jido.AgentServer.members(desk, :auditor)

{:ok, replace} = LiveGuide.Desk.replace_auditor_signal()
{:ok, _accepted, _directives} = Jido.AgentServer.call(desk, replace)
:ok = Jido.AgentServer.await_ready(desk)

[new_auditor] = Jido.AgentServer.members(desk, :auditor)
true = new_auditor != old_auditor
"recount" = Jido.AgentServer.agent(new_auditor).state.station
[^first] = Jido.AgentServer.members(desk, :packers)
```

Removal stops the member and everything it owns. The owner keeps running.

```elixir
{:ok, remove} = LiveGuide.Desk.remove_packers_signal()
{:ok, _accepted, _directives} = Jido.AgentServer.call(desk, remove)
:ok = Jido.AgentServer.await_ready(desk)

[] = Jido.AgentServer.members(desk, :packers)
false = Process.alive?(first)
```

## Redirect a connection

A connection's identity is its source, destination, and path. To change a destination, remove the old connection and add the new one in one batch. Member processes do not change.

AgentServer finishes applying the change before it runs the Turn's other Directives. An `emit` in the same batch therefore follows the new connection.

```elixir
[auditor] = Jido.AgentServer.members(desk, :auditor)
[backup] = Jido.AgentServer.members(desk, :backup)

{:ok, redirect} = LiveGuide.Desk.redirect_signal(%{items: 3})
{:ok, _accepted, _directives} = Jido.AgentServer.call(desk, redirect)
:ok = Jido.AgentServer.await_ready(desk)

true = wait_until.(fn -> Jido.AgentServer.agent(backup).state.packed == 3 end)
0 = Jido.AgentServer.agent(auditor).state.packed
[^auditor] = Jido.AgentServer.members(desk, :auditor)
```

## Rejected changes

Validation covers the complete candidate before commit. A rejected Turn returns an error and leaves the state, revision, and processes as they were.

Repeating the redirect fails because the old connection no longer exists.

```elixir
before = Jido.AgentServer.snapshot(desk)
children = Jido.AgentServer.children(desk)

{:error, %{code: :not_found}} = Jido.AgentServer.call(desk, redirect)

^before = Jido.AgentServer.snapshot(desk)
^children = Jido.AgentServer.children(desk)
```

Runtime child Directives do not work on member names. Change a member with a mutation.

```elixir
{:ok, stop_member} = LiveGuide.Desk.stop_member_signal()
{:error, :topology_agent_requires_mutation} = Jido.AgentServer.call(desk, stop_member)

:ok = Jido.stop_agent(LiveGuide.Jido, desk)
```

## Directive reference

All of these are in `Jido.Agent.Directive`. Options for `count` and `initial_state` default to 1 and `%{}`.

| Directive | Effect on data | Effect on processes |
| --- | --- | --- |
| `agent_add/3` | Adds a member. | Starts its slots. |
| `agent_update/2` | Merges `:definition`, `:count`, or `:initial_state`. | A count change starts or stops slots. A change to `:definition` or `:initial_state` restarts every slot. |
| `agent_replace/3` | Replaces the whole entry. | Restarts the slots if the bound definition or state changed. |
| `agent_remove/1` | Removes a member. | Stops its slots and subtrees. |
| `connection_add/2` | Adds an edge. | None. |
| `connection_update/2` | Merges `changes:`, which accepts only `:delivery`. | None. |
| `connection_replace/2` | Replaces the edge with the same identity. | None. |
| `connection_remove/2` | Removes an edge. | None. |
| `topology_set/1` | Replaces all members and connections. | Applies the difference. Unchanged slots keep running. |

A state change to a field that a member's `count` or `initial_state` refers to has the same effect as editing that value.

These validation codes are the most common:

| Code | Cause |
| --- | --- |
| `:already_exists` | Adding a member or connection whose identity exists. |
| `:not_found` | Updating, replacing, or removing one that does not exist. |
| `:unknown_endpoint` | Removing a member that a connection still names, or connecting to an undeclared endpoint. Remove those connections in the same batch. |
| `:counted_delivery` | A member's count is no longer 1 and a connection to it uses `:single`. |
| `:unaccepted_type` | The destination has no route for the connection's path. |
| `:unknown_fields` | An update names a field that it cannot change. |

## What happens if the change fails after commit

Validation cannot prove that a process will start. If a new member fails to start or does not become ready in `:readiness_timeout`, the committed definition stands and the owner stops. [Topology Reconciliation](topology-reconciliation.md) describes this path.

## Related

- [Topology Reconciliation](topology-reconciliation.md) explains which processes restart and why.
- [Durable Topology](../durability/durable-topology.md) covers saved topology changes.
- [Live Reconfiguration](../plugins/plugin-live-reconfiguration.md) covers Plugin changes.
