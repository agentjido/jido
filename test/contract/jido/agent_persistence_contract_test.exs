defmodule JidoTest.Contract.AgentPersistenceTest do
  use Covenant.Case, component: "jido.agent", async: true
  alias Jido.Agent
  alias Jido.Agent.Directive, as: D
  alias Jido.Persistence, as: P
  alias Jido.Persistence.{ETS, Record}
  alias JidoTest.AgentContract, as: F

  defmodule Worker do
    use Jido.Agent, name: "saved_worker"

    agent do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      route "test.run", F.Return
    end
  end

  defmodule Team do
    use Jido.Agent, name: "persistent_team", vsn: 7

    agent do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(2)})
    end

    routes do
      route "test.run", F.Return
    end

    topology do
      agent :first, Worker
      agent :workers, Worker, count: state(:count), initial_state: %{count: state(:count)}

      connections do
        connect "test.run", from: :root, to: :first
      end
    end
  end

  defmodule Custom do
    use Jido.Agent, name: "custom_snapshot", vsn: 3

    agent do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(2)})
    end

    def checkpoint(agent, context) do
      if context[:observer], do: send(context.observer, :dumped)
      {:ok, %{id: agent.id, saved: agent.state.count}}
    end

    def restore(payload, context) do
      if context[:observer], do: send(context.observer, :restored)

      Map.get_lazy(context, :result, fn ->
        instantiate(id: payload.id, state: %{count: payload.saved})
      end)
    end
  end

  setup do
    store = {ETS, table: :"snapshot_contract_#{System.unique_integer([:positive])}"}
    %{store: store, opts: [namespace: "snapshot-contract"]}
  end

  @tag obligation: "jido.agent.I36"
  test "state and ordered definition edits form one complete candidate" do
    source = Team.instantiate!(id: "team")
    effects = [D.agent_update(:first, %{initial_state: %{count: 4}}), D.route_add("next")]

    assert {:ok, candidate, ^effects} =
             Agent.cmd(source, F.signal(%{output: %{count: 4}, directives: effects}))

    assert candidate.state == %{count: 4}
    assert hd(candidate.topology.agents).initial_state == %{count: 4}
    assert Enum.map(candidate.routes, & &1.path) == ["test.run", "next"]
    assert source == Team.instantiate!(id: "team")
    assert {:error, _} = Agent.cmd(source, F.signal(%{directives: effects ++ [:invalid]}))

    assert {:error, _} =
             Agent.cmd(source, F.signal(%{output: %{count: "bad"}, directives: effects}))
  end

  @tag obligation: ["jido.agent.I37", "jido.agent.I45"]
  test "one saved Agent freezes member definitions and retains symbolic input declarations" do
    agent = Team.instantiate!(id: "frozen", state: %{count: 4})
    assert {:ok, saved} = P.snapshot(agent)
    assert saved.format == 1
    assert %Agent{id: "frozen", state: %{count: 4}} = saved.agent
    assert Enum.all?(saved.agent.topology.agents, &is_struct(&1.definition, Agent))
    assert Enum.at(saved.agent.topology.agents, 1).count == Agent.Topology.state(:count)
    assert {:ok, restored} = P.restore(saved)
    assert restored === saved.agent
    assert {:ok, members} = Agent.Topology.bind(restored, restored.state)
    assert Enum.at(members, 1).count == 4
    assert Enum.at(members, 1).state == %{count: 4}
    assert Team.definition().topology === agent.topology
  end

  @tag obligation: ["jido.agent.I37", "jido.agent.I38"]
  test "custom state converters cannot replace the saved definition or identity" do
    agent = %{
      Custom.instantiate!(id: "custom")
      | topology: %{Team.definition().topology | connections: []}
    }

    assert {:ok, saved} = P.snapshot(agent, context: %{observer: self()})
    assert_receive :dumped
    assert {:ok, restored} = P.restore(saved, context: %{observer: self()})
    assert_receive :restored
    assert restored.topology === saved.agent.topology
    assert restored.state === agent.state

    for result <- [{:ok, :invalid}, {:ok, Custom.instantiate!(id: "wrong")}] do
      assert {:error, _} = P.restore(saved, context: %{result: result})
    end

    assert {:error, :rejected} = P.restore(saved, context: %{result: {:error, :rejected}})
  end

  @tag obligation: "jido.agent.I38"
  test "invalid envelopes and changed code fail before a custom converter runs" do
    {:ok, saved} = P.snapshot(Custom.instantiate!(id: "preflight"))

    for invalid <- [
          Map.delete(saved, :references),
          Map.put(saved, :extra, true),
          %{saved | format: 99},
          %{saved | references: %{}}
        ] do
      assert {:error, _} = P.restore(invalid, context: %{observer: self()})
      refute_received :restored
    end

    refs = Map.new(saved.references, fn {module, _} -> {module, <<0::128>>} end)
    assert {:error, _} = P.restore(%{saved | references: refs}, context: %{observer: self()})
    refute_received :restored
  end

  @tag obligation: ["jido.agent.I38", "jido.agent.I39"]
  test "nonportable values and legacy checkpoint envelopes are rejected" do
    agent = Custom.instantiate!(id: "portable")

    assert {:error, _} =
             P.snapshot(%{agent | metadata: %{pid: self()}}, context: %{observer: self()})

    refute_received :dumped

    for legacy <- [%{version: 2, id: agent.id, state: agent.state}, %{fmt: 3}, %{fmt: 4}] do
      assert {:error, _} = P.restore(legacy, context: %{observer: self()})
      refute_received :restored
    end
  end

  @tag obligation: "jido.agent.I39"
  test "format, definition version and storage revision have separate meanings" do
    agent = Team.instantiate!(id: "versioned")
    assert Team.vsn() == 7
    {:ok, saved} = P.snapshot(%{agent | vsn: 8})
    assert saved.format == 1
    assert saved.agent.vsn == 8
    assert {:ok, %{vsn: 8}} = P.restore(saved)
  end

  @tag obligation: ["jido.agent.I38", "jido.agent.I40"]
  test "one record saves definition and state and fences stale writes", c do
    agent = Team.instantiate!(id: "revision")
    assert :ok = P.create_agent(c.store, agent, c.opts)
    assert {:ok, next, _} = Agent.mutate(agent, [D.route_add("next")])
    next = %{next | state: %{count: 4}}
    assert :ok = P.save_agent(c.store, next, c.opts ++ [revision: 1, expected_revision: 0])
    assert {:ok, restored, 1} = P.load_agent_with_revision(c.store, Team, agent.id, c.opts)
    assert restored.routes === next.routes
    assert restored.state === next.state
    {ETS, store_opts} = c.store
    key = P.agent_key(Agent.Ref.new!(namespace: c.opts[:namespace], id: agent.id))
    {:ok, bytes} = ETS.get(key, store_opts)
    {:ok, record} = Record.decode(bytes)
    assert %{fmt: 4, vsn: 7, rev: 1, checkpoint: %{format: 1, agent: %Agent{}}} = record

    for opts <- [[revision: 1, expected_revision: 0], [revision: 1, expected_revision: 1]] do
      assert {:error, _} = P.save_agent(c.store, agent, c.opts ++ opts)
      assert {:ok, ^bytes} = ETS.get(key, store_opts)
    end

    assert :ok = P.delete_agent(c.store, Team, agent.id, c.opts)
    assert {:error, :deleted} = P.load_agent(c.store, Team, agent.id, c.opts)

    assert {:error, :conflict} =
             P.save_agent(c.store, next, c.opts ++ [revision: 2, expected_revision: 1])
  end
end
