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

{:ok, root} = Jido.start_agent(TopologyGuide.Jido, TopologyGuide.Team, id: "team")
:ok = Server.await_ready(root)

member_ids = fn name ->
  for {id, _pid} <- Enum.sort(Jido.list_agents(TopologyGuide.Jido)),
      String.starts_with?(id, "team/$topology/#{name}/"),
      do: id
end

["team/$topology/triage/1/initial" = triage_id] = member_ids.(:triage)

["team/$topology/responders/1/initial", "team/$topology/responders/2/initial"] =
  member_ids.(:responders)
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

{:ok, triage_address} = Jido.agent_address(TopologyGuide.Jido, triage_id)
{:ok, triage} = Jido.resolve_agent(TopologyGuide.Jido, triage_address)
handle = Jido.Signal.new!("ticket.handle", %{}, source: "/guides/durable_topology")

{:ok, %{status: :committed}} = Server.call(triage, handle)

%{agent_revision: 1, agent: %{state: %{handled: 1}}} = Server.snapshot(triage)
%{agent_revision: 0} = Server.snapshot(root)
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

await_replacement = fn address, old ->
  Enum.find_value(1..300, fn _attempt ->
    with {:ok, pid} when pid != old <- Jido.resolve_agent(TopologyGuide.Jido, address),
         :ok <- Server.await_ready(pid) do
      pid
    else
      _other ->
        Process.sleep(10)
        nil
    end
  end)
end

new_triage = await_replacement.(triage_address, triage)

^triage_id = Server.snapshot(new_triage).agent.id
%{handled: 1} = Server.snapshot(new_triage).agent.state
```

When a root's server or activation dies, the root restores first, then reconciles its members. The owned member activations restart, so member PIDs change. Each member reads its own record, so its ID, state, and any pending Flow Turn survive.

## Stop and reactivate a team

Stopping the root stops the whole activation. Activate the root by Address to restore its members. A member with a saved running Turn resumes from that receipt. If reconciling a member returns `:topology_owner_required`, activate or reconcile its owner first.

```elixir
alias Jido.AgentServer, as: Server

:ok = Jido.stop_agent(TopologyGuide.Jido, root)
0 = Jido.resident_agent_count(TopologyGuide.Jido)

{:ok, root_address} = Jido.agent_address(TopologyGuide.Jido, "team")
{:ok, root} = Jido.activate_agent(TopologyGuide.Jido, root_address)
:ok = Server.await_ready(root)

{:ok, thawed_triage} = Jido.resolve_agent(TopologyGuide.Jido, triage_address)
^triage_id = Server.snapshot(thawed_triage).agent.id
%{handled: 1} = Server.snapshot(thawed_triage).agent.state
%{agent_revision: 1} = Server.snapshot(thawed_triage)
```

The instance supervisor restarts a failed Registry or Runic Runner. Resident
activations stop when either dependency stops. The application can activate
each durable root again by Address after the dependency starts. The root
restores its members.

During reconciliation, the root loads each member's record. A found record is restored, a `:not_found` read creates the member, and any other error stops the root's readiness.

## Change members safely

The root's revision commits a topology change together with its state. Slot identities follow these rules:

- A slot keeps its identity while the member's definition and bound initial state stay the same and the slot number is within the count.
- Shrinking the count retires the higher slots. Growing it again gives those slots new identities, and therefore new IDs and fresh state.
- Removing a member and adding it back gives new identities, and a pending Turn of the old member does not come back.
- Changing the member's definition or bound initial state gives all its slots new identities.

A retired identity's record stays in the store. Jido does not collect it and has no public listing of member records. A complete definition upgrade can replace the static topology while the activation is idle.

## Send to one member with durable acceptance

Return one of these directives from a Turn:

```elixir
# Root to one declared child slot
Jido.Agent.Directive.emit(signal, {:durable, {:agent, :responders, 2}})

# Declared child to its parent
Jido.Agent.Directive.emit(signal, {:durable, :parent})
```

Both Agents must have persistence in the same named Jido instance. The
receiver must prepare a durable Flow for the Signal. The sender can use an
Action or a Flow. A missing slot, a slot marked for removal, an unsupported
target, or a non-portable outbound Signal fails the sender Turn before
commit. Dynamic children, Bus routes, and fan-out are outside this API.

The sender commits its next state, the prepared Signal, the destination
Address, and a new handoff ID in one Agent record write. The slot identity
in the Address fixes which member can receive the send. Replacing a slot
does not redirect an existing send to its replacement.

A resident sender tries its oldest pending send when it is idle and admission
is open. It retries a rejected, busy, or unavailable receiver after a delay.
Each attempt has an admission deadline. An expired attempt can confirm an
earlier acceptance, but it cannot start a new Turn. A non-durable receiver or a route that cannot prepare a durable Flow rejects
acceptance. A pending send delays later sends while its destination is unavailable. The
sender drops the send if the destination is deleted, the owner has removed the
member, or the owner's current topology has retired that identity. Status
reports the pending count, oldest send age in milliseconds, and last failure. Explicit hibernation or a shutdown pauses
delivery until the sender is resident again. A pending send prevents
automatic idle passivation of its sender. Delivery does not start a
passivated receiver.

The receiver writes the running Flow receipt and the acceptance ID in one
write before it acknowledges. The Flow can then finish, wait, or fail
independently. A repeated delivery of that ID gives the same acknowledgment
even after later Turns replace the running receipt. The sender removes the
send from its record after acknowledgment. This removal changes the
persistence revision but does not change the Agent revision. When the store
confirms that it rejected the removal before writing, the sender retries
the removal without sending the Signal again. A conflict or an uncertain
write stops the sender until reconciliation reads its record.

Send order applies to durable sends from one sender. Best-effort effects run
through their existing path and can be lost in a crash. An acknowledgment
does not prove that any receiver effect ran. A receiver keeps the latest
receipt from each sender. The next handoff from that sender proves it has
removed the previous handoff from its saved outbox. Jido keeps earlier
receipts with no sender identity. If the receiver already holds 16,384
receipts and cannot replace one, it returns `:topology_receipt_capacity`.
Existing IDs still return their acknowledgment.

The [durable handoff example](../../examples/13_durable_execution/13_14_topology_handoff/README.md)
shows a pending send restored after an activation stops.

## Deploy across the topology record change

The current reader accepts earlier format-3 records. Earlier Jido builds can
reject format-3 records that contain the `:topology_owner` field or store
sender Addresses in accepted handoff receipts.

Stop earlier Jido processes that use the store and back up the store before
you deploy. After the new build writes either record shape, keep a reader that
supports both shapes. To run the earlier binary, stop the new processes and
restore the backup. Restoring the backup discards writes made since it was taken.

## Know the limits

- **No family snapshot.** A root snapshot captures the logical topology, not the state of its running members. After a crash, members are each at their own last commit, and two members can reflect different points in a shared process. Keep invariants that span Agents in one Agent's state, or make your Flows tolerate this.
- **No family upgrade.** `Jido.Persistence.upgrade_agent/5` changes one record. Upgrade the root and each member separately.
- **Best-effort output.** Ordinary member outputs and connection deliveries are post-commit effects. They are not replayed. See [Recovery Limits](recovery-and-effect-limits.md).
- **No family delete.** `Jido.delete_agent/3` on the root leaves member records in place. An Address with a generated member ID under a deleted owner stays reserved, including when an older record has no explicit owner field. Use IDs outside this pattern for standalone Agents. Do not delete one member of a family you will restore, because the root's reconciliation reads `:deleted` and fails.

```elixir
alias Jido.AgentServer, as: Server

:ok = Jido.stop_agent(TopologyGuide.Jido, root)
:ok = Jido.delete_agent(TopologyGuide.Jido, root_address)

{:error, :deleted} = Jido.Persistence.load_agent(TopologyGuide.Jido, TopologyGuide.Team, "team")

{:ok, %{state: %{handled: 1}}} =
  Jido.Persistence.load_agent(TopologyGuide.Jido, TopologyGuide.Agent, triage_id)

:ok = Jido.delete_agent(TopologyGuide.Jido, triage_address)

:ok = Jido.stop(TopologyGuide.Jido)
```

## Next steps

- [Declare Agent Topology](../composition/declare-agent-topology.livemd) explains static members.
- [Durable Turns and Flows](durable-turns-and-flows.livemd) covers member Flow recovery.
- [Deletion and Tombstones](deletion-and-tombstones.md) covers the remaining records.
