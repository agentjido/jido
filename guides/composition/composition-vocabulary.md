# Composition Vocabulary

This guide defines the terms that the Compose Agents guides use and helps you choose between declared members and runtime children.

Jido composes Agents in two ways. A definition can declare its members as data, or a running Agent can start children during a Turn. Both produce the same kind of process, an AgentServer activation under an owner. They differ in who decides that the process should exist.

## The terms in one definition

```elixir
defmodule VocabularyGuide.Packer do
  use Jido.Agent, name: "vocabulary_packer"

  routes do
    route "order.pack" do
      action _input, context: context do
        {:ok, context.agent_state}
      end
    end
  end
end

defmodule VocabularyGuide.Desk do
  use Jido.Agent, name: "vocabulary_desk"

  topology do
    agent :packers, VocabularyGuide.Packer, count: 2

    connections do
      connect "order.pack", from: :root, to: :packers, delivery: :broadcast
    end
  end
end

%{agents: [%{name: :packers, count: 2}], connections: [%{from: %{kind: :agent, name: :root}}]} =
  VocabularyGuide.Desk.definition().topology
```

## Definition terms

These terms describe data. Reading or building them starts no process.

| Term | Meaning |
| --- | --- |
| Topology | The `:agents` and `:connections` data on an Agent definition, read through `Jido.Agent.Topology`. |
| Member | One named entry in `:agents`. It holds a definition or module, a `count`, and an `initial_state`. The name `:root` is reserved. |
| Count | How many copies of a member to run. It is a positive integer or a reference to a parent state field. |
| State reference | A value from `Jido.Agent.Topology.state/1`, written `state(:key)` in the DSL. Jido reads the named parent state field when it binds the member. |
| Connection | One edge in `:connections`. It selects output by Signal type (`path`), source (`from`), and destination (`to`). |
| Endpoint | The source or destination of a connection. It is a member name, `:root` for the enclosing Agent, or `bus(:name)` for a declared local Bus. |
| Delivery | The `:delivery` field of a connection, `:single` or `:broadcast`. A destination with a count other than 1 must use `:broadcast`. |
| Local Bus | A `Jido.Signal.Bus` that the `Jido.Plugin.Bus.DSL` Plugin declares and the owner's activation supervises. |

## Runtime terms

These terms describe live processes.

| Term | Meaning |
| --- | --- |
| Activation | The supervisor tree for one Agent. `Jido.AgentServer.activation/1` returns its root PID. |
| Owner | The AgentServer whose activation holds a member or child. |
| Slot | One running copy of a member, numbered from 1. |
| Runtime child | An Agent started by `Jido.AgentServer.Directive.agent_start/3` or `Jido.AgentServer.spawn_child/4`. It does not appear in the definition. |
| Tag | The atom or string that names a runtime child under its owner. Tags of topology members are generated and are not part of the API. |
| Placement | Where a runtime child runs. `:owned` is under the parent's activation. `:independent` is under the instance supervisor. |
| Binding | Resolving member counts and initial state from one parent state value. `Jido.Agent.Topology.bind/3` does this without starting processes. |
| Reconciliation | The step where AgentServer makes live members and Buses match the bound topology. See [Topology Reconciliation](topology-reconciliation.md). |

## Choose members or runtime children

Use a member when the Agent always needs that collaborator or when the group size follows Agent state. Use a runtime child when a Turn decides that work needs its own process, such as one Agent per request.

| Question | Declared member | Runtime child |
| --- | --- | --- |
| Who decides that it exists? | The definition, plus state references | A Turn or a caller |
| Where is the intent saved? | In the Agent's topology, which a parent snapshot includes | Nowhere, unless your own state records it |
| Restarted after the owner's worker crashes? | Yes, by reconciliation | Owned children no. Independent children keep running. |
| Addressed by | Member name, with all slots receiving the Signal | Its tag |
| Stopped by | A mutation, such as `Jido.Agent.Directive.agent_remove/1` | `Jido.AgentServer.Directive.agent_stop/2` or `Jido.AgentServer.stop_child/3` |
| Can outlive its owner? | No | Yes, with `placement: :independent` |

The two do not mix for one name. A runtime Directive that starts or stops a member name fails with `:topology_agent_requires_mutation`.

## What composition does not include

Delivery between Agents uses best-effort casts, and each Agent commits its own Turn. There is no transaction across Agents, no durable acknowledgement, and no coordinated snapshot of an Agent family. Members and children run on the local node, and a remote `:node` on `agent_start/3` is rejected.

## Next steps

- [Declare Agent Topology](declare-agent-topology.livemd) builds a definition with members.
- [Connect Agent Outputs](connect-agent-outputs.livemd) routes Signals between members.
- [Parent and Child Agents](parent-and-child-agents.md) starts Agents during a Turn.
