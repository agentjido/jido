defmodule Jido.Agent.MutationTest do
  use ExUnit.Case, async: true
  alias Jido.Agent
  alias Jido.Agent.{Diff, Directive, Error, Route}
  alias JidoTest.AgentEvolutionFixtures, as: F

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

    assert original == F.agent()
  end

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
  end

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
  end

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
  end

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

  test "Plugin state initialization, configuration, migration, and removal stay explicit" do
    assert {:ok, added, _} = Agent.mutate(F.agent(), [Directive.plugin_add(F.Counter)])
    assert added.state == %{count: 0, counter: 3}
    assert {:ok, configured, _} = Agent.mutate(added, [Directive.plugin_configure(F.Counter, [])])
    assert configured.state == added.state
    assert {:error, _} = Agent.mutate(added, [Directive.plugin_remove(F.Counter)])
    assert {:error, _} = Agent.mutate(added, [Directive.plugin_configure(F.Counter, key: :other)])

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
  end

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

  test "current route contract survives removal and the next input uses the new routes" do
    original = F.agent()
    remove = Directive.route_remove("run")
    assert {:ok, next, [^remove]} = Agent.cmd(original, F.signal([remove]))
    assert {:error, %Error{code: :unmatched_input}} = Agent.cmd(next, F.signal([]))
    assert original.routes != []
  end

  test "mutations do not create helper functions" do
    assert {:ok, _, _} =
             Agent.mutate(F.agent(), [Directive.route_add("dynamic", F.Work, as: :dynamic)])

    refute function_exported?(F.Worker, :dynamic_signal, 0)
  end
end
