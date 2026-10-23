Code.require_file("../support.ex", __DIR__)

defmodule JidoTest.AgentServer.Effects.RuntimeDirectivesTest do
  use JidoTest.Case, async: true
  use Covenant.Case, component: "jido.agent_server.effects", async: true

  import JidoTest.Eventually
  alias Jido.Agent.Directive, as: D
  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.Directive, as: R
  alias Jido.AgentServer.Effects
  alias JidoTest.AgentEvolutionFixtures, as: E

  defmodule Initializer do
    use Jido.Agent, name: "effect_initializer"

    def initialize(%{observer: observer}, _context) do
      send(observer, :initialized)
      {:ok, %{}}
    end
  end

  @tag obligation: "jido.agent_server.effects.I10"
  test "runtime directives start, send to, reply from, and stop an Agent", c do
    server = start(c, partition: "effects")
    child = %{E.agent() | id: unique_id("runtime-child")}

    assert {:ok, _, _} =
             turn(server, [
               R.agent_start(child, :worker, restart: :permanent, meta: %{role: :worker})
             ])

    settled(server)
    assert %{worker: %{pid: worker}} = Server.children(server)
    assert Server.agent(worker).id == child.id
    assert %{jido: jido, partition: "effects"} = Server.status(worker)
    assert jido == c.jido

    assert {:ok, _, _} =
             turn(server, [
               R.agent_send(
                 :worker,
                 E.signal([D.route_add("extra", E.Work, state: %{source: :output, path: []})])
               )
             ])

    settled(server)
    assert_eventually(length(Server.agent(worker).routes) == 2)

    assert {:ok, _, _} =
             turn(worker, [
               R.parent_send(
                 E.signal([D.route_add("reply", E.Work, state: %{source: :output, path: []})])
               )
             ])

    settled(worker)
    assert_eventually(length(Server.agent(server).routes) == 2)
    assert {:ok, _, _} = turn(server, [R.agent_stop(:worker)])
    settled(server)
    assert Server.children(server) == %{}
    refute Process.alive?(worker)
  end

  @tag obligation: "jido.agent_server.effects.I10"
  test "runtime directives reject remote placement and bad options before commit", c do
    server = start(c)
    initial = Server.snapshot(server)

    for directive <- [
          R.agent_start(E.Worker, :worker, node: :remote@invalid),
          R.agent_start(E.Worker, :worker, opts: %{unknown: true}),
          R.agent_start(E.Worker, :worker, opts: %{partition: "other"}),
          R.agent_start(E.Worker, :worker, opts: %{agent: E.agent()}),
          R.agent_start(E.Worker, nil),
          R.agent_start(E.Worker, "$topology/worker"),
          R.parent_send(E.signal([]))
        ] do
      assert {:error, _} =
               turn(server, [
                 D.route_add("never", E.Work, state: %{source: :output, path: []}),
                 directive
               ])

      assert Server.snapshot(server) == initial
      assert Server.children(server) == %{}
    end

    assert {:ok, _, _} =
             turn(server, [
               R.agent_start(Initializer, :worker,
                 opts: %{id: "explicit", state: %{observer: self()}},
                 restart: :temporary
               )
             ])

    settled(server)
    assert Server.agent(Server.children(server).worker.pid).id == "explicit"
    assert_received :initialized
    refute_received :initialized

    instance = %{E.agent() | id: unique_id("instance-options")}

    for opts <- [%{id: "other"}, %{state: %{count: 2}}] do
      assert {:error, _} = turn(server, [R.agent_start(instance, :conflict, opts: opts)])
      refute Map.has_key?(Server.children(server), :conflict)
    end

    assert {:ok, _, _} =
             turn(server, [R.agent_start(E.Worker, :derived, node: node(), restart: :temporary)])

    settled(server)
    derived = Server.children(server).derived.pid
    assert Server.agent(derived).id == Server.agent(server).id <> "/derived"
  end

  @tag obligation: "jido.agent_server.effects.I10"
  test "runtime target admission rejects missing activation and topology-owned names", c do
    config = config(c)

    assert {:error, :activation_required} =
             Effects.validate_batch([R.agent_send(:worker, E.signal([]))], %{
               config
               | activation: nil
             })

    assert {:error, :invalid_agent_name} =
             Effects.validate_batch([R.agent_stop("")], config)

    assert {:error, :reserved_agent_name} =
             Effects.validate_batch([R.agent_send("$topology/worker", E.signal([]))], config)

    config = put_in(config.agent.topology.agents, [%{name: :worker}])

    assert {:error, :topology_agent_requires_mutation} =
             Effects.validate_batch([R.agent_stop(:worker)], config)
  end

  defp start(c, opts \\ []) do
    agent = %{E.agent() | id: unique_id("effect-runtime")}
    assert {:ok, server} = Jido.start_agent(c.jido, agent, opts)
    assert :ok = Server.await_ready(server)
    server
  end

  defp turn(server, directives), do: Server.call(server, E.signal(directives))

  defp settled(server) do
    assert_eventually(Server.status(server).phase == :idle)
    :ok
  end

  defp config(c) do
    %{
      activation: self(),
      agent: E.agent(),
      default_dispatch: nil,
      directive_handler: nil,
      jido: c.jido,
      max_directives_per_turn: 10,
      parent: self(),
      partition: nil,
      plugin_specs: [],
      runner: Jido.exec_runner_name(c.jido)
    }
  end
end
