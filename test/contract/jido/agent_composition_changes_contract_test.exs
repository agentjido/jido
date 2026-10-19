defmodule JidoTest.Contract.AgentCompositionChangesTest do
  use Covenant.Case, component: "jido.agent", async: true
  alias Jido.Agent
  alias Jido.Agent.{Diff, Directive, Topology}
  alias JidoTest.AgentContract, as: F

  defmodule Worker do
    use Jido.Agent, name: "composition_worker"

    routes do
      route "test.run", F.Return
    end
  end

  defmodule Counter do
    use Jido.Plugin, vsn: 2

    def state_spec(opts),
      do:
        {Keyword.get(opts, :key, :counter),
         Zoi.integer() |> Zoi.default(Keyword.get(opts, :start, 3))}

    def dump(value, _, _), do: {:ok, %{value: value}}
    def load(%{value: value}, _, _), do: {:ok, value}
  end

  defmodule Migrations do
    def add(value, n), do: {:ok, value + n}
  end

  defp cmd(agent, changes), do: Agent.cmd(agent, F.signal(%{directives: changes}))

  @tag obligation: "jido.agent.I41"
  test "strict noun_verb edits preserve order and replace omitted fields with defaults" do
    source = F.instance()

    changes = [
      Directive.agent_add(:a, Worker, count: 2),
      Directive.agent_add(:b, Worker),
      Directive.agent_update(:a, %{count: 3}),
      Directive.agent_replace(:a, Worker)
    ]

    assert {:ok, next, ^changes} = cmd(source, changes)
    assert Enum.map(next.topology.agents, & &1.name) == [:a, :b]
    assert hd(next.topology.agents).count == 1

    for changes <- [
          [Directive.agent_add(:a, Worker)],
          [Directive.agent_remove(:missing)],
          [Directive.agent_update(:a, %{name: :renamed})],
          [Directive.agent_add(:a, Worker), Directive.agent_remove(:a)]
        ] do
      assert {:error, _} = cmd(next, changes)
    end

    assert source.topology == %{agents: [], connections: []}
  end

  @tag obligation: ["jido.agent.I36", "jido.agent.I41", "jido.agent.I42"]
  test "the final graph resolves after the batch and removals do not cascade" do
    source = F.instance()

    assert {:ok, next, _} =
             cmd(source, [
               Directive.connection_add("test.run", from: :root, to: :worker),
               Directive.agent_add(:worker, Worker)
             ])

    assert {:error, %{code: :unknown_endpoint}} = cmd(next, [Directive.agent_remove(:worker)])

    assert {:ok, empty, _} =
             cmd(next, [
               Directive.agent_remove(:worker),
               Directive.connection_remove("test.run", from: :root, to: :worker)
             ])

    assert empty.topology == source.topology

    for field <- [:groups, :resources, :relationships, :imports, :exports, :topologies] do
      assert {:error, _} = cmd(source, [Directive.topology_set(%{field => []})])
    end
  end

  @tag obligation: ["jido.agent.I41", "jido.agent.I42"]
  test "counted destinations need broadcast after the complete batch" do
    assert {:ok, next, _} =
             cmd(F.instance(), [
               Directive.connection_add("test.run",
                 from: :root,
                 to: :worker,
                 delivery: :broadcast
               ),
               Directive.agent_add(:worker, Worker, count: 2)
             ])

    assert {:error, %{code: :counted_delivery}} =
             cmd(next, [
               Directive.connection_update("test.run",
                 from: :root,
                 to: :worker,
                 changes: %{delivery: :single}
               )
             ])
  end

  @tag obligation: ["jido.agent.I36", "jido.agent.I41"]
  test "route edits have strict identities and the Diff reports net changes" do
    source = F.instance()

    assert {:ok, next, diff} =
             Agent.mutate(source, [
               Directive.route_add("other"),
               Directive.route_update("test.run", %{defaults: %{amount: 2}}),
               Directive.routes_reorder(["other", "test.run"])
             ])

    assert Enum.map(next.routes, & &1.path) == ["other", "test.run"]
    assert [%{path: "other"}] = diff.routes.added
    assert [%{before: %{defaults: %{}}, after: %{defaults: %{amount: 2}}}] = diff.routes.updated
    assert diff.routes.order == %{before: ["test.run"], after: ["other", "test.run"]}
    assert {:error, _} = Agent.mutate(next, [Directive.routes_reorder(["other"])])
    assert {:error, _} = Agent.mutate(next, [Directive.route_update("other", %{path: "renamed"})])

    assert {:ok, ^source, diff} =
             Agent.mutate(source, [Directive.route_add("other"), Directive.route_remove("other")])

    assert Diff.empty?(diff)
  end

  @tag obligation: "jido.agent.I43"
  test "Plugin changes preserve state and require explicit migration and disposal" do
    source = F.instance()
    assert {:ok, added, _} = cmd(source, [Directive.plugin_add(Counter)])
    assert added.state.counter == 3
    assert {:ok, configured, _} = cmd(added, [Directive.plugin_configure(Counter, start: 99)])
    assert configured.state.counter == 3
    assert {:error, _} = cmd(added, [Directive.plugin_remove(Counter)])
    assert {:error, _} = cmd(added, [Directive.plugin_add(Counter)])
    assert {:error, _} = cmd(added, [Directive.plugin_configure(Counter, key: :renamed)])

    assert {:ok, migrated, _} =
             cmd(added, [
               Directive.plugin_configure(Counter, [key: :renamed],
                 migrate: {Migrations, :add, [2]}
               )
             ])

    assert migrated.state.renamed == 5
    refute Map.has_key?(migrated.state, :counter)
    assert {:ok, removed, _} = cmd(migrated, [Directive.plugin_remove(Counter, state: :discard)])
    assert removed.state === source.state
    assert Agent.runtime_plugins(removed) == []
  end

  @tag obligation: ["jido.agent.I42", "jido.agent.I45"]
  test "binding copies one state value without replacing the authored references" do
    definition =
      F.definition(
        topology: %{
          agents: [%{name: :workers, definition: Worker, count: Topology.state(:count)}]
        }
      )

    source = Agent.instantiate!(definition, id: "bound", state: %{count: 2})
    assert {:ok, [%{name: :workers, count: 2}]} = Topology.bind(source, source.state)
    assert source.topology === definition.topology
    assert {:ok, changed, []} = Agent.cmd(source, F.signal(%{output: %{source.state | count: 4}}))
    assert changed.topology === source.topology
    assert {:ok, [%{count: 4}]} = Topology.bind(changed, changed.state)
  end

  @tag obligation: "jido.agent.I43"
  test "an affected Plugin cannot change configuration and run its owned directives in one batch" do
    assert {:error, _} = cmd(F.instance(), [Directive.plugin_add(F.Effects), %F.Effect{value: 1}])
    assert {:ok, owned, _} = cmd(F.instance(), [Directive.plugin_add(F.Effects)])

    assert {:error, _} =
             cmd(owned, [Directive.plugin_configure(F.Effects, []), %F.Effect{value: 1}])

    assert {:ok, next, [%F.Effect{}]} = cmd(owned, [%F.Effect{value: 1}])
    assert next.state.effects == 1
  end
end
