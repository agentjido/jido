Code.require_file("../support.ex", __DIR__)
Code.require_file("../plugin_runtime/configuration_support.ex", __DIR__)

defmodule JidoTest.AgentServer.Composition.CommitTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server.composition", async: false
  alias Jido.Agent
  alias Jido.Agent.Directive
  alias Jido.AgentServer, as: Server
  alias JidoTest.AgentServer.PluginRuntime.ConfigurationSupport, as: Support
  alias Support.{Cache, Observer}
  alias JidoTest.AgentServer.Fixtures, as: F
  @moduletag capture_log: true

  defmodule Worker do
    use Jido.Agent, name: "composition_runtime_worker"

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0), context: Zoi.map()})
      initial_state %{count: 1}
    end

    @impl Jido.Agent
    def initialize(state, context),
      do: {:ok, state |> Map.put(:count, 2) |> Map.put(:context, context)}

    routes do
      route "work", JidoTest.AgentServer.Fixtures.Work do
        state(from: output())
      end
    end
  end

  setup do
    observer = Module.concat(__MODULE__, "Observer#{System.unique_integer([:positive])}")
    Process.register(self(), observer)
    Map.put(F.setup_runtime(), :observer, observer)
  end

  defp agent(topology \\ %{}, plugins \\ []), do: Support.agent(topology, plugins)

  defp turn(server, directives),
    do: Server.call(server, F.signal(%{mode: :batch, directives: directives}))

  @tag obligation: "jido.agent_server.composition.I5"
  test "route mutations commit as data and a failed batch keeps the revision", c do
    server = F.start(%{c | agent: agent()})

    directive =
      Directive.route_add("other", %{kind: :action, target: F.Work},
        state: %{source: :output, path: []}
      )

    assert {:ok, accepted, [^directive]} = turn(server, [directive])
    assert Enum.map(accepted.routes, & &1.path) == ["work", "other"]
    assert Server.status(server).state_version == 1
    assert {:error, _} = turn(server, [Directive.route_remove("missing")])
    assert Server.agent(server) == accepted
    assert Server.status(server).state_version == 1
    assert {:ok, next, []} = Server.call(server, F.signal(%{}, "other"))
    assert next.state.count == 2
  end

  @tag obligation: [
         "jido.agent_server.composition.I5",
         "jido.agent_server.composition.I6",
         "jido.agent_server.composition.I8"
       ]
  test "topology mutations start accepted members", c do
    initial = agent()
    assert :ok = Server.CompositionRuntime.validate_runtime(%{agent: initial})
    member = Directive.agent_add(:worker, Worker)
    assert {:ok, candidate, _} = Agent.mutate(initial, [member])
    assert :ok = Server.CompositionRuntime.validate_runtime(%{agent: candidate})
    server = F.start(%{c | agent: initial})
    assert {:ok, _, [^member]} = turn(server, [member])
    assert :ok = Server.await_ready(server)
    assert Server.agent(server).topology == candidate.topology
    assert Server.status(server).state_version == 1
    assert map_size(Server.children(server)) == 1

    [%{pid: child}] = Map.values(Server.children(server))
    assert %{id: id, state: %{count: 2, context: context}} = Server.agent(child)
    assert context == %{id: id, parent_id: "composed", member: :worker, slot: 1}
  end

  @tag obligation: "jido.agent_server.composition.I5"
  test "an accepted Plugin declaration is committed before runtime handoff", c do
    server = F.start(%{c | agent: agent()})
    assert {:ok, accepted, _} = turn(server, [Directive.plugin_add(Cache, observer: c.observer)])
    assert Server.status(server).state_version == 1
    assert Agent.runtime_plugins(accepted) != []
    assert_receive {:plugin_started, _, %{plugin_state: 5, state_version: 1}}
    assert :ok = Server.await_ready(server)
  end

  @tag obligation: "jido.agent_server.composition.I5"
  test "a bare worker rejects composition changes before committing", c do
    bare =
      start_supervised!(%{
        id: make_ref(),
        start: {Server, :start_link, [[agent: agent(), runner: c.runner]]}
      })

    assert {:error, _} = turn(bare, [Directive.plugin_add(Observer, observer: c.observer)])
    assert Agent.runtime_plugins(Server.agent(bare)) == []
    assert Server.status(bare).state_version == 0
    assert Server.alive?(bare)
  end
end
