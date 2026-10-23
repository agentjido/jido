Code.require_file("../support.ex", __DIR__)

defmodule JidoTest.AgentServer.Composition.RuntimeRulesTest do
  use JidoTest.Case, async: true
  use Covenant.Case, component: "jido.agent_server.composition", async: true

  alias Jido.Agent
  alias Jido.Agent.Diff
  alias Jido.Agent.Directive, as: D
  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.{CompositionRuntime, TopologyBus, TopologyRuntime}
  alias JidoTest.AgentEvolutionFixtures, as: E
  alias JidoTest.AgentServer.Fixtures, as: F
  import JidoTest.Eventually

  defmodule QueueProvider do
    use Jido.Agent.Extension, id: "composition.queue"
    def endpoint_kinds, do: [:queue]
    def endpoints(data), do: [%{kind: :queue, name: data.name}]
  end

  defp extension(provider, data) do
    %{id: provider.id(), provider: provider, vsn: provider.vsn(), data: data}
  end

  @tag obligation: "jido.agent_server.composition.I6"
  test "durable member identities retain only the same accepted slots" do
    assert {:ok, added, _} = Agent.mutate(E.agent(), [D.agent_add(:workers, E.Worker, count: 2)])
    declaration = Map.put(hd(added.topology.agents), :identities, %{1 => "one", 2 => "two"})
    added = put_in(added.topology.agents, [declaration])

    assert {:ok, initial} = TopologyRuntime.identify(nil, added)
    assert hd(initial.topology.agents).identities == %{1 => "one", 2 => "two"}

    assert {:ok, grown, _} = Agent.mutate(initial, [D.agent_update(:workers, %{count: 3})])
    assert {:ok, grown} = TopologyRuntime.identify(initial, grown)
    grown_ids = hd(grown.topology.agents).identities
    assert grown_ids[1] == "one"
    assert grown_ids[2] == "two"
    assert is_binary(grown_ids[3]) and grown_ids[3] not in ["one", "two"]

    assert {:ok, smaller, _} = Agent.mutate(grown, [D.agent_update(:workers, %{count: 1})])
    assert {:ok, smaller} = TopologyRuntime.identify(grown, smaller)
    assert hd(smaller.topology.agents).identities == %{1 => "one"}

    assert {:ok, regrown, _} = Agent.mutate(smaller, [D.agent_update(:workers, %{count: 2})])
    assert {:ok, regrown} = TopologyRuntime.identify(smaller, regrown)
    regrown_ids = hd(regrown.topology.agents).identities
    assert regrown_ids[1] == "one"
    assert is_binary(regrown_ids[2]) and regrown_ids[2] not in ["one", "two", grown_ids[2]]

    assert {:ok, changed, _} =
             Agent.mutate(regrown, [D.agent_update(:workers, %{initial_state: %{count: 7}})])

    assert {:ok, changed} = TopologyRuntime.identify(regrown, changed)
    changed_ids = hd(changed.topology.agents).identities
    assert changed_ids[1] != regrown_ids[1]
    assert changed_ids[2] != regrown_ids[2]
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
          extensions: [queue],
          topology: %{
            agents: [],
            connections: [%{path: "**", from: from, to: to}]
          }
        })
        |> Agent.instantiate!(id: "unsupported-runtime-endpoint")

      assert {:error, %{code: :unsupported_runtime_endpoint, path: [:topology, :connections]}} =
               TopologyRuntime.validate(agent)
    end

    assert TopologyRuntime.buses(%{E.agent() | extensions: [queue]}) == []
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
        extensions: [queue, bus],
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

    assert {:error, %{code: :unsupported_runtime_endpoint}} = TopologyRuntime.validate(agent)

    plain = E.agent()
    with_bus = %{plain | extensions: [bus]}
    assert TopologyRuntime.changed?(Diff.between(plain, with_bus), plain, with_bus)

    assert {:error, :activation_required} =
             CompositionRuntime.check(
               %{agent: plain, activation: nil, plugin_specs: []},
               with_bus,
               []
             )
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

    assert :ok = TopologyRuntime.emit(root_context, F.signal())
    assert_eventually(Server.agent(server).state.count == 1)

    output = F.signal()

    assert :ok =
             TopologyRuntime.emit(
               %{root_context | default_dispatch: {:pid, target: self()}},
               output
             )

    assert_receive {:signal, ^output}

    child = %{F.agent() | id: unique_id("manual-child")}
    assert {:ok, child} = Server.spawn_child(server, child, :manual)
    assert :ok = Server.await_ready(child)
    assert :ok = TopologyRuntime.send_agent(state, :manual, F.signal())
    assert_eventually(Server.agent(child).state.count == 1)

    parent = Server.status(child).parent
    assert :ok = TopologyRuntime.parent_send(parent, F.signal())
    assert_eventually(Server.agent(server).state.count == 2)

    assert {:error, :agent_not_found} = TopologyRuntime.send_agent(state, :missing, F.signal())
    assert {:error, :parent_not_found} = TopologyRuntime.parent_send(nil, F.signal())
    assert :ok = TopologyRuntime.member_output(%{activation_state: state}, :missing, F.signal())
    assert {:error, :bus_not_ready} = TopologyBus.publish(state, :missing, F.signal())

    root = parent.activation
    assert :ok = Server.stop(server)
    F.down(root)
    assert {:error, :parent_not_found} = TopologyRuntime.parent_send(parent, F.signal())
  end
end
