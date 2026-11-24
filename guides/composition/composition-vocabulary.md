# Composition Vocabulary

An Agent definition can declare members that start with its activation. Application code can also start Agents as work arrives and assign runtime ownership when needed.

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
| Count | How many copies of a member to run. It is a positive integer in the definition. |
| Connection | One edge in `:connections`. It selects output by Signal type (`path`), source (`from`), and destination (`to`). |
| Endpoint | The source or destination of a connection. It is a member name, `:root` for the enclosing Agent, or `bus(:name)` for a declared local Bus. |
| Delivery | The `:delivery` field of a connection, `:single` or `:broadcast`. A destination with a count other than 1 must use `:broadcast`. |
| Local Bus | A `Jido.Signal.Bus` that the `Jido.Plugin.Bus.DSL` Plugin declares and the owner's activation supervises. |

## Runtime terms

These terms describe live processes.

| Term | Meaning |
| --- | --- |
| Activation | The internal supervisor tree for one resident Agent. The public API exposes semantic status, not the root PID. |
| Owner | The AgentServer whose activation holds a declared member. |
| Slot | One running copy of a member, numbered from 1. |
| Agent started by the application | An Agent that the application starts with `Jido.start_agent/3` and manages by ID. It can acquire a runtime owner through `Jido.transfer_agent_ownership/4`. |
| Binding | Resolving member definitions and returning their static count and initial state. `Jido.Agent.Topology.bind/3` does this without starting processes. |

## Choose how to start an Agent

| Question | Declared member | Agent started by the application |
| --- | --- | --- |
| Who decides that it exists? | The topology definition | Application code |
| Addressed by | Member name in routes and connections | Application-assigned Agent ID and partition |
| Observed with | A scoped `Jido.list_agents/2` call and snapshots | `Jido.whereis_agent/3` and a snapshot |
| Stopped by | The owner stopping, or `Jido.AgentServer.remove_topology_member/4` for one slot | `Jido.stop_agent/3`, or the current runtime owner stopping |

## Next steps

- [Declare Agent Topology](declare-agent-topology.livemd) builds a definition with members.
- [Connect Agent Outputs](connect-agent-outputs.livemd) routes Signals between members.
- [Parent and Child Agents](parent-and-child-agents.md) sends work to a declared member.
