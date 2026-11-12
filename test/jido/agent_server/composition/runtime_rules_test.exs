defmodule Jido.AgentServer.Composition.RuntimeRulesTest do
  use Jido.Test.Case, async: false
  use Covenant.Case, component: "jido.agent_server.composition", async: false

  alias Jido.Agent
  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.Topology
  alias Jido.Test.Agent.EvolutionFixtures, as: E
  alias Jido.Test.AgentServer.Contract, as: F
  import Jido.Test.Eventually

  defmodule QueueProvider do
    use Jido.Plugin, id: "composition.queue"
    def endpoint_kinds, do: [:queue]
    def endpoints(data), do: [%{kind: :queue, name: data.name}]
  end

  defp extension(provider, data) do
    %{id: provider.id(), provider: provider, vsn: provider.vsn(), data: data}
  end

  @tag obligation: "jido.agent_server.composition.I5"
  test "runtime validation rejects provider endpoints that have no live implementation" do
    queue = extension(QueueProvider, %{name: :jobs, buses: [%{name: :not_a_bus}]})

    for {from, to} <- [
          {%{kind: :queue, name: :jobs}, %{kind: :agent, name: :root}},
          {%{kind: :agent, name: :root}, %{kind: :queue, name: :jobs}}
        ] do
      agent =
        Agent.define!(%{
          name: "unsupported_runtime_endpoint",
          schema: E.agent().schema,
          routes: E.agent().routes,
          plugins: [queue],
          topology: %{
            agents: [],
            connections: [%{path: "**", from: from, to: to}]
          }
        })
        |> Agent.instantiate!(id: "unsupported-runtime-endpoint")

      assert {:error, %{code: :unsupported_runtime_endpoint, path: [:topology, :connections]}} =
               Topology.validate(agent)
    end

    assert Topology.buses(%{E.agent() | plugins: [queue]}) == []
  end

  @tag obligation: "jido.agent_server.composition.I5"
  test "a declared Bus does not make another provider endpoint executable" do
    queue = extension(QueueProvider, %{name: :events})
    bus = extension(Jido.Plugin.Bus.DSL, %{buses: [%{name: :events}]})

    agent =
      Agent.define!(%{
        name: "runtime_endpoint_kind",
        schema: E.agent().schema,
        routes: E.agent().routes,
        plugins: [queue, bus],
        topology: %{
          agents: [],
          connections: [
            %{
              path: "**",
              from: %{kind: :queue, name: :events},
              to: %{kind: :agent, name: :root}
            }
          ]
        }
      })
      |> Agent.instantiate!(id: "runtime-endpoint-kind")

    assert {:error, %{code: :unsupported_runtime_endpoint}} = Topology.validate(agent)

    with_bus = %{E.agent() | plugins: [bus]}
    assert Topology.requires_activation?(with_bus)
  end

  @tag obligation: "jido.agent_server.composition.I8"
  test "root fallback, manual child delivery, and stale targets have explicit results", c do
    root_agent = %{F.agent() | id: unique_id("composition-fallback")}
    assert {:ok, server} = Jido.start_agent(c.jido, root_agent)
    assert :ok = Server.await_ready(server)
    state = :gen_statem.call(server, :child_context).state

    root_context = %{
      agent: root_agent,
      parent: nil,
      default_dispatch: nil,
      server: server,
      jido: c.jido
    }

    assert :ok = Topology.emit(root_context, F.signal())
    assert_eventually(Server.agent(server).state.count == 1)

    output = F.signal()

    assert :ok =
             Topology.emit(
               %{root_context | default_dispatch: {:pid, target: self()}},
               output
             )

    assert_receive {:signal, ^output}

    child = %{F.agent() | id: unique_id("manual-child")}
    assert {:ok, child} = Server.spawn_child(server, child, :manual)
    assert :ok = Server.await_ready(child)
    assert :ok = Topology.send_agent(state, :manual, F.signal())
    assert_eventually(Server.agent(child).state.count == 1)

    parent = :gen_statem.call(child, :parent)
    assert :ok = Topology.parent_send(parent, F.signal())
    assert_eventually(Server.agent(server).state.count == 2)

    assert {:error, :agent_not_found} = Topology.send_agent(state, :missing, F.signal())
    assert {:error, :parent_not_found} = Topology.parent_send(nil, F.signal())
    assert :ok = Topology.member_output(%{activation_state: state}, :missing, F.signal())
    assert {:error, :bus_not_ready} = Topology.publish(state, :missing, F.signal())

    root = parent.activation
    assert :ok = Server.stop(server)
    F.down(root)
    assert {:error, :parent_not_found} = Topology.parent_send(parent, F.signal())
  end
end
