# Durable Topology

This guide explains how a persistent topology saves and restores its root and members, and what the combined result does not promise. It assumes you can declare members. [Declare Agent Topology](../composition/declare-agent-topology.livemd) covers that.

## Give the root persistence

Members need no durable declaration. A member inherits its root's instance, partition, and persistence settings, so start the root with `persistence:` and every member becomes durable.

The next code starts a support team with one triage Agent and two responders.

```elixir
defmodule TopologyGuide.Agent do
  use Jido.Agent, name: "topology_guide_agent"

  state do
    schema Jido.Joi.object(%{handled: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/guides/durable_topology"

    route "ticket.handle" do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        {:ok, %{handled: context.agent_state.handled + 1}}
      end
    end
  end
end

defmodule TopologyGuide.Team do
  use Jido.Agent, name: "topology_guide_team"

  topology do
    agent :triage, TopologyGuide.Agent
    agent :responders, TopologyGuide.Agent, count: 2
  end
end

alias Jido.AgentServer, as: Server

{:ok, _} =
  Jido.start_link(
    name: TopologyGuide.Jido,
    namespace: "guides/durable-topology",
    persistence: {Jido.Persistence.ETS, table: :durable_topology_guide}
  )

{:ok, root} = Jido.start_agent(TopologyGuide.Jido, TopologyGuide.Team, id: "team", persistence: :inherit)
:ok = Server.await_ready(root)

member_ids = fn root, name ->
  root |> Server.members(name) |> Enum.map(&Server.snapshot(&1).agent.id)
end

["team/$topology/triage/1/initial"] = member_ids.(root, :triage)

["team/$topology/responders/1/initial", "team/$topology/responders/2/initial"] =
  member_ids.(root, :responders)
```

## Know what each record holds

The root and every member have separate records:

| Record | Holds |
| --- | --- |
| Root | The root's state and definition, including nested member definitions, counts, connections, and the identity of each slot |
| Member | That member's state, definition, revision, and latest Turn receipt |

A member ID has the form `<root id>/$topology/<member name>/<slot>/<identity>`. Slots count from 1. The identity is `initial` in the first lifetime of a slot and a new UUIDv7 in later ones.

A member commits on its own revision, so member work does not change the root's revision.

```elixir
alias Jido.AgentServer, as: Server

[triage] = Server.members(root, :triage)
handle = Jido.Signal.new!("ticket.handle", %{}, source: "/guides/durable_topology")

{:ok, %{state: %{handled: 1}}, []} = Server.call(triage, handle)

%{state_version: 1} = Server.snapshot(triage)
%{state_version: 0} = Server.snapshot(root)
```

## Lose a member or a root

When a member's server dies, its activation restarts it from its record. Its siblings and root keep running. Topology members are `restart: :permanent` children, and their activations live under the root's activation.

```elixir
alias Jido.AgentServer, as: Server

triage_id = Server.snapshot(triage).agent.id
monitor = Process.monitor(triage)
Process.exit(triage, :kill)

receive do
  {:DOWN, ^monitor, :process, ^triage, :killed} -> :ok
end

await_replacement = fn root, name, old ->
  Enum.find_value(1..300, fn _attempt ->
    with [pid] when pid != old <- Server.members(root, name),
         :ok <- Server.await_ready(pid) do
      pid
    else
      _other ->
        Process.sleep(10)
        nil
    end
  end)
end

new_triage = await_replacement.(root, :triage, triage)

^triage_id = Server.snapshot(new_triage).agent.id
%{handled: 1} = Server.snapshot(new_triage).agent.state
```

When a root's server or activation dies, the root restores first, then reconciles its members. The owned member activations restart, so member PIDs change. Each member reads its own record, so its ID, state, and any pending Flow Turn survive.

## Hibernate and thaw a team

`Jido.AgentServer.hibernate/2` on the root saves the root and stops the whole activation, members included. It waits only for the root's own Turn to settle. A member's Flow Turn that is still running keeps its `:running` receipt, and it resumes after the thaw like any other durable Turn.

```elixir
alias Jido.AgentServer, as: Server

:ok = Server.hibernate(root)
0 = Jido.agent_count(TopologyGuide.Jido)

{:ok, root} = Jido.thaw(TopologyGuide.Jido, TopologyGuide.Team, "team")
:ok = Server.await_ready(root)

[thawed_triage] = Server.members(root, :triage)
^triage_id = Server.snapshot(thawed_triage).agent.id
%{handled: 1} = Server.snapshot(thawed_triage).agent.state
%{state_version: 1} = Server.snapshot(thawed_triage)
```

During reconciliation, the root loads each member's record. A found record is restored, a `:not_found` read creates the member, and any other error stops the root's readiness.

## Change members safely

The root's revision commits a topology change together with its state. Slot identities follow these rules:

- A slot keeps its identity while the member's definition and bound initial state stay the same and the slot number is within the count.
- Shrinking the count retires the higher slots. Growing it again gives those slots new identities, and therefore new IDs and fresh state.
- Removing a member and adding it back gives new identities, and a pending Turn of the old member does not come back.
- Changing the member's definition or bound initial state gives all its slots new identities.

A retired identity's record stays in the store. Jido does not collect it and has no public listing of member records. A complete definition upgrade can replace the static topology while the activation is idle.

## Know the limits

- **No family snapshot.** A root snapshot captures the logical topology, not the state of its running members. After a crash, members are each at their own last commit, and two members can reflect different points in a shared process. Keep invariants that span Agents in one Agent's state, or make your Flows tolerate this.
- **No family upgrade.** `Jido.Persistence.upgrade_agent/5` changes one record. Upgrade the root and each member separately.
- **No output recovery.** Member outputs and connection deliveries are post-commit effects, so they are not replayed. See [Recovery Limits](recovery-and-effect-limits.md).
- **No family delete.** `Jido.delete_agent/4` on the root leaves member records in place. The next code shows this. Do not delete one member of a family you will restore, because the root's reconciliation reads `:deleted` and fails.

```elixir
alias Jido.AgentServer, as: Server

:ok = Server.stop(root)

{:ok, root_ref} = Jido.agent_ref(TopologyGuide.Jido, "team")
:ok = Jido.delete_agent(TopologyGuide.Jido, root_ref, TopologyGuide.Team)

{:error, :deleted} = Jido.Persistence.load_agent(TopologyGuide.Jido, TopologyGuide.Team, "team")

{:ok, %{state: %{handled: 1}}} =
  Jido.Persistence.load_agent(TopologyGuide.Jido, TopologyGuide.Agent, triage_id)

{:ok, member_ref} = Jido.agent_ref(TopologyGuide.Jido, triage_id)
:ok = Jido.delete_agent(TopologyGuide.Jido, member_ref, TopologyGuide.Agent)

:ok = Jido.stop(TopologyGuide.Jido)
```

## Next steps

- [Declare Agent Topology](../composition/declare-agent-topology.livemd) explains static members.
- [Durable Turns and Flows](durable-turns-and-flows.livemd) covers member Flow recovery.
- [Deletion and Tombstones](deletion-and-tombstones.md) covers the remaining records.
