defmodule Jido.Agent.MutationTest do
  use Covenant.Case, component: "jido.agent", async: true
  alias Jido.Agent
  alias Jido.Agent.{Diff, Directive, Error, Mutation, Route}
  alias JidoTest.AgentEvolutionFixtures, as: F

  defmodule InvalidMigrations do
    def invalid(_value), do: :invalid
  end

  defmodule PassiveExtension do
    use Jido.Agent.Extension, id: "test.mutation.passive"
  end

  @tag obligation: "jido.agent.I27"
  test "the mutation Directive set is closed and exact" do
    modules = [
      Directive.AgentAdd,
      Directive.AgentUpdate,
      Directive.AgentReplace,
      Directive.AgentRemove,
      Directive.RouteAdd,
      Directive.RouteUpdate,
      Directive.RouteReplace,
      Directive.RouteRemove,
      Directive.RoutesSet,
      Directive.RoutesReorder,
      Directive.ConnectionAdd,
      Directive.ConnectionUpdate,
      Directive.ConnectionReplace,
      Directive.ConnectionRemove,
      Directive.TopologySet,
      Directive.PluginAdd,
      Directive.PluginConfigure,
      Directive.PluginRemove
    ]

    assert Mutation.modules() === modules

    for module <- modules do
      assert Mutation.mutation?(struct(module)) === true
    end

    assert Mutation.mutation?(:invalid) === false
    assert Mutation.mutation?(%Jido.Agent.Directive.Emit{signal: nil}) === false
  end

  @tag obligation: "jido.agent.I27"
  test "agent CRUD preserves order and replacement resets omitted fields" do
    original = F.agent()

    assert {:ok, first, diff} =
             Agent.mutate(original, [
               Directive.agent_add(:a, F.Worker, count: 2),
               Directive.agent_add(:b, F.Worker),
               Directive.agent_update(:a, %{initial_state: %{count: 8}}),
               Directive.agent_replace(:a, F.Worker)
             ])

    assert Enum.map(first.topology.agents, & &1.name) == [:a, :b]
    assert hd(first.topology.agents).count == 1
    assert hd(first.topology.agents).initial_state == %{}
    assert length(diff.agents.added) == 2
    assert original.topology.agents == []
    assert {:ok, last, diff} = Agent.mutate(first, [Directive.agent_remove(:a)])
    assert Enum.map(last.topology.agents, & &1.name) == [:b]
    assert [%{name: :a}] = diff.agents.removed
  end

  @tag obligation: ["jido.agent.I26", "jido.agent.I27"]
  test "operation preconditions fail with an index and preserve the source" do
    original = F.agent()

    for changes <- [
          [Directive.agent_remove(:missing)],
          [Directive.agent_update(:missing, %{count: 2})],
          [Directive.agent_replace(:missing, F.Worker)],
          [Directive.agent_add(:a, F.Worker), Directive.agent_add(:a, F.Worker)]
        ] do
      assert {:error, %Error{path: [:directives, index]}} = Agent.mutate(original, changes)
      assert index == length(changes) - 1
    end

    assert {:error,
            %Error{
              code: :not_found,
              path: [:directives, 0],
              details: %{collection: :agents, key: :missing}
            }} = Agent.mutate(original, [Directive.agent_remove(:missing)])

    assert {:ok, with_agent, _} = Agent.mutate(original, [Directive.agent_add(:a, F.Worker)])

    assert {:error,
            %Error{
              code: :already_exists,
              path: [:directives, 0],
              details: %{collection: :agents, key: :a}
            }} = Agent.mutate(with_agent, [Directive.agent_add(:a, F.Worker)])

    assert original == F.agent()
  end

  @tag obligation: "jido.agent.I27"
  test "unknown fields and identity edits fail instead of adding hidden data" do
    for d <- [
          Directive.agent_update(:a, %{name: :b}),
          Directive.route_update("run", %{path: "other"}),
          Directive.connection_update("work", from: :root, to: :a, changes: %{from: :b})
        ] do
      assert {:error, %Error{code: :unknown_fields}} = Agent.mutate(F.agent(), [d])
    end

    assert_raise ArgumentError, fn -> Directive.agent_add(:a, F.Worker, count: 1, count: 2) end
    assert_raise ArgumentError, fn -> Directive.route_add("work", F.Work, typo: true) end
  end

  @tag obligation: ["jido.agent.I26", "jido.agent.I28"]
  test "only the final graph must resolve and removals do not cascade" do
    assert {:ok, added, _} =
             Agent.mutate(F.agent(), [
               Directive.connection_add("work", from: :root, to: :a),
               Directive.agent_add(:a, F.Worker)
             ])

    assert {:error, %Error{code: :unknown_endpoint}} =
             Agent.mutate(added, [Directive.agent_remove(:a)])

    assert {:ok, removed, _} =
             Agent.mutate(added, [
               Directive.agent_remove(:a),
               Directive.connection_remove("work", from: :root, to: :a)
             ])

    assert removed.topology == %{agents: [], connections: []}

    unavailable = Module.concat(__MODULE__, UnavailableAction)

    assert {:ok, without_transient_route, _} =
             Agent.mutate(F.agent(), [
               Directive.routes_set([
                 %{path: "transient", handler: %{kind: :action, target: unavailable}}
               ]),
               Directive.route_remove("transient")
             ])

    assert without_transient_route.routes == []
  end

  @tag obligation: "jido.agent.I27"
  test "connection CRUD uses endpoint/path identity and replacement defaults" do
    assert {:ok, agent, _} =
             Agent.mutate(F.agent(), [
               Directive.agent_add(:a, F.Worker),
               Directive.connection_add("work", from: :root, to: :a),
               Directive.connection_update("work",
                 from: :root,
                 to: :a,
                 changes: %{delivery: :broadcast}
               )
             ])

    assert hd(agent.topology.connections).delivery == :broadcast

    assert {:ok, agent, _} =
             Agent.mutate(agent, [Directive.connection_replace("work", from: :root, to: :a)])

    assert hd(agent.topology.connections).delivery == :single

    assert {:error, _} =
             Agent.mutate(agent, [Directive.connection_add("work", from: :root, to: :a)])

    assert {:error, _} =
             Agent.mutate(agent, [Directive.connection_remove("absent", from: :root, to: :a)])

    root = %{kind: :agent, name: :root}
    child = %{kind: :agent, name: :explicit}

    assert {:ok, explicit, _} =
             Agent.mutate(F.agent(), [
               Directive.agent_add(:explicit, F.Worker),
               Directive.connection_add("work", from: root, to: child)
             ])

    assert [%{from: ^root, to: ^child}] = explicit.topology.connections
  end

  @tag obligation: "jido.agent.I27"
  test "route add accepts executable modules and all descriptor forms" do
    assert {:ok, agent, _} =
             Agent.mutate(F.agent(), [
               Directive.route_add("action", F.Work, defaults: %{amount: 1}),
               Directive.route_add("transform", %{
                 kind: :transform,
                 target: {F.Transform, :run, 1}
               }),
               Directive.route_add("pass")
             ])

    assert {:ok, %{handler: %{kind: :action}}} = Route.select(agent, "action")
    assert {:ok, %{handler: %{kind: :transform}}} = Route.select(agent, "transform")
    assert {:ok, %{handler: %{kind: :pass_through}}} = Route.select(agent, "pass")
  end

  @tag obligation: "jido.agent.I27"
  test "route update shallow replaces defaults and route replacement fills defaults" do
    assert {:ok, agent, _} =
             Agent.mutate(F.agent(), [
               Directive.route_update("run", %{defaults: %{nested: %{one: 1, two: 2}}}),
               Directive.route_update("run", %{defaults: %{nested: %{one: 3}}})
             ])

    assert hd(agent.routes).defaults == %{nested: %{one: 3}}
    assert {:ok, replaced, _} = Agent.mutate(agent, [Directive.route_replace("run", F.Work)])
    assert hd(replaced.routes).defaults == %{}
    assert {:ok, empty, _} = Agent.mutate(replaced, [Directive.route_remove("run")])
    assert empty.routes == []

    assert {:ok, updated, _} =
             Agent.mutate(F.agent(), [
               Directive.route_update("run", %{as: :run_work, emits: ["work.done"]}),
               Directive.agent_add(:worker, F.Worker),
               Directive.agent_update(:worker, %{definition: F.Worker})
             ])

    assert [%{as: :run_work, emits: ["work.done"]}] = updated.routes
    assert [%{definition: F.Worker}] = updated.topology.agents
  end

  @tag obligation: "jido.agent.I27"
  test "route reorder changes first-match selection and rejects incomplete permutations" do
    assert {:ok, broad, _} =
             Agent.mutate(F.agent(), [
               Directive.route_add("event.**"),
               Directive.route_add("event.one", F.Work)
             ])

    assert {:ok, %{path: "event.**"}} = Route.select(broad, "event.one")

    assert {:ok, exact, diff} =
             Agent.mutate(broad, [Directive.routes_reorder(["run", "event.one", "event.**"])])

    assert {:ok, %{path: "event.one"}} = Route.select(exact, "event.one")
    assert diff.routes.updated == []
    refute Diff.empty?(diff)

    for paths <- [[], ["run"], ["run", "run", "event.**"], ["run", "event.one", "unknown"]] do
      assert {:error, _} = Agent.mutate(broad, [Directive.routes_reorder(paths)])
    end
  end

  @tag obligation: "jido.agent.I27"
  test "routes_set preserves order and rejects invalid contracts and helper collisions" do
    assert {:ok, agent, _} = Agent.mutate(F.agent(), [Directive.routes_set([])])
    assert agent.routes == []

    for edits <- [
          [Directive.route_add("bad", %{kind: :pass_through}, defaults: %{x: 1})],
          [Directive.route_add("bad", %{kind: :pass_through}, emits: [])],
          [Directive.route_add("bad.*", F.Work, as: :bad)],
          [
            Directive.route_add("a", F.Work, as: :same),
            Directive.route_add("b", F.Work, as: :same)
          ],
          [Directive.route_add("run")]
        ] do
      assert {:error, _} = Agent.mutate(F.agent(), edits)
    end
  end

  @tag obligation: "jido.agent.I28"
  test "removing an accepted input checks existing connections at the final boundary" do
    root =
      Agent.define!(%{name: "root", routes: [%{path: "work", handler: %{kind: :pass_through}}]})
      |> Agent.instantiate!(id: "root")

    assert {:ok, agent, _} =
             Agent.mutate(root, [
               Directive.agent_add(:a, F.Worker),
               Directive.connection_add("work", from: :a, to: :root)
             ])

    assert {:error, %Error{code: :unaccepted_type}} =
             Agent.mutate(agent, [Directive.route_remove("work")])

    assert {:ok, _, _} =
             Agent.mutate(agent, [
               Directive.route_remove("work"),
               Directive.connection_remove("work", from: :a, to: :root)
             ])
  end

  @tag obligation: ["jido.agent.I26", "jido.agent.I27"]
  test "cancelled edits and set-to-original produce an empty Diff" do
    original = F.agent()

    assert {:ok, ^original, diff} =
             Agent.mutate(original, [
               Directive.agent_add(:a, F.Worker),
               Directive.agent_remove(:a)
             ])

    assert Diff.empty?(diff)

    assert {:ok, ^original, diff} =
             Agent.mutate(original, [Directive.topology_set(original.topology)])

    assert Diff.empty?(diff)
  end

  @tag obligation: "jido.agent.I29"
  test "Plugin state initialization, configuration, migration, and removal stay explicit" do
    assert {:ok, added, _} = Agent.mutate(F.agent(), [Directive.plugin_add(F.Counter)])
    assert added.state == %{count: 0, counter: 3}
    assert {:ok, configured, _} = Agent.mutate(added, [Directive.plugin_configure(F.Counter, [])])
    assert configured.state == added.state

    assert {:error, %Error{code: :plugin_state_discard_required, details: %{plugin: F.Counter}}} =
             Agent.mutate(added, [Directive.plugin_remove(F.Counter)])

    assert {:error, %Error{code: :plugin_migration_required, details: %{plugin: F.Counter}}} =
             Agent.mutate(added, [Directive.plugin_configure(F.Counter, key: :other)])

    assert {:ok, migrated, _} =
             Agent.mutate(added, [
               Directive.plugin_configure(F.Counter, [key: :other],
                 migrate: {F.Migrations, :add, [2]}
               )
             ])

    assert migrated.state == %{count: 0, other: 5}

    assert {:ok, removed, _} =
             Agent.mutate(migrated, [Directive.plugin_remove(F.Counter, state: :discard)])

    assert removed.state == F.agent().state
    assert removed.extensions == []

    assert {:ok, explicit, _} =
             Agent.mutate(F.agent(), [Directive.plugin_add(F.Counter, [], initial: 9)])

    assert explicit.state.counter == 9

    assert {:ok, stateless, _} =
             Agent.mutate(F.agent(), [Directive.plugin_add(JidoTest.AgentContract.Stateless)])

    assert stateless.state === F.agent().state

    for migrate <- [
          {F.Migrations, :add, :invalid},
          {F.Migrations, "add", []},
          {"module", :add, []}
        ] do
      assert {:error, %Error{code: :invalid_plugin_change}} =
               Agent.mutate(added, [Directive.plugin_configure(F.Counter, [], migrate: migrate)])
    end

    assert {:error, %Error{code: :invalid_plugin_migration}} =
             Agent.mutate(added, [
               Directive.plugin_configure(F.Counter, [],
                 migrate: {InvalidMigrations, :invalid, []}
               )
             ])
  end

  @tag obligation: "jido.agent.I29"
  test "Plugin edit errors identify the Plugin and retain passive contributions" do
    assert {:error, %Error{code: :plugin_not_found, details: %{plugin: F.Counter}}} =
             Agent.mutate(F.agent(), [Directive.plugin_configure(F.Counter, [])])

    assert {:ok, added, _} = Agent.mutate(F.agent(), [Directive.plugin_add(F.Counter)])

    assert {:error, %Error{code: :plugin_exists, details: %{plugin: F.Counter}}} =
             Agent.mutate(added, [Directive.plugin_add(F.Counter)])

    conflict =
      Agent.define!(%{
        name: "plugin_conflict",
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(1)})
      })
      |> Agent.instantiate!(id: "plugin-conflict")

    assert {:error, %Error{code: :plugin_state_conflict, details: %{key: :count}}} =
             Agent.mutate(conflict, [
               Directive.plugin_add(F.Counter, key: :count)
             ])

    passive = %{
      id: PassiveExtension.id(),
      provider: PassiveExtension,
      vsn: PassiveExtension.vsn(),
      data: %{}
    }

    source =
      Agent.define!(%{name: "passive", extensions: [passive]})
      |> Agent.instantiate!(id: "passive")

    assert {:ok, next, _} = Agent.mutate(source, [Directive.plugin_add(F.Counter)])
    assert hd(next.extensions) === passive
  end

  @tag obligation: "jido.agent.I29"
  test "changed Plugin detection compares declarations in both directions" do
    before = F.agent()
    assert {:ok, after_agent, _} = Agent.mutate(before, [Directive.plugin_add(F.Counter)])

    assert Mutation.changed_plugins(before, after_agent) === [F.Counter]
    assert Mutation.changed_plugins(after_agent, before) === [F.Counter]
    assert Mutation.changed_plugins(after_agent, after_agent) === []

    assert Mutation.changed_plugins(
             after_agent,
             after_agent,
             [Directive.plugin_configure(F.Counter, [])]
           ) === [F.Counter]

    assert {:error, %Error{code: :plugin_change_with_owned_directive}} =
             Mutation.validate_effects(
               before,
               after_agent,
               [Directive.plugin_add(F.Counter), %F.Owned{}]
             )

    assert {:error, %Error{code: :plugin_change_with_owned_directive}} =
             Agent.cmd(
               after_agent,
               F.signal([Directive.plugin_remove(F.Counter, state: :discard), %F.Owned{}])
             )
  end

  @tag obligation: "jido.agent.I26"
  test "invalid state, malformed batches, and runtime work fail without a candidate" do
    for changes <- [
          nil,
          :bad,
          [Directive.agent_remove(:a) | :bad],
          [Jido.AgentServer.Directive.server_stop()],
          [42]
        ] do
      assert {:error, _} = Agent.mutate(F.agent(), changes)
    end

    assert {:error, _} = Agent.mutate(%{F.agent() | state: %{count: "bad"}}, [])
  end

  @tag obligation: "jido.agent.I27"
  test "current route contract survives removal and the next input uses the new routes" do
    original = F.agent()
    remove = Directive.route_remove("run")
    assert {:ok, next, [^remove]} = Agent.cmd(original, F.signal([remove]))
    assert {:error, %Error{code: :unmatched_input}} = Agent.cmd(next, F.signal([]))
    assert original.routes != []
  end

  @tag obligation: "jido.agent.I27"
  test "mutations do not create helper functions" do
    assert {:ok, _, _} =
             Agent.mutate(F.agent(), [Directive.route_add("dynamic", F.Work, as: :dynamic)])

    refute function_exported?(F.Worker, :dynamic_signal, 0)
  end
end
