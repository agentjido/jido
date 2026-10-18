defmodule Jido.Agent.MutationFoundationTest do
  use ExUnit.Case, async: true
  alias Jido.Agent
  alias Jido.Agent.Diff
  alias Jido.Agent.Directive, as: D
  alias JidoTest.AgentEvolutionFixtures, as: F

  test "Diff reports exact final values and order for each collection and state" do
    before = F.agent()

    assert {:ok, after_agent, diff} =
             Agent.mutate(before, [
               D.route_replace("run", F.Flow, defaults: %{amount: 2}),
               D.route_add("new"),
               D.agent_add(:a, F.Worker),
               D.plugin_add(F.Counter)
             ])

    assert diff.routes.added == [Enum.at(after_agent.routes, 1)]
    assert diff.routes.removed == []
    assert diff.routes.updated == [%{before: hd(before.routes), after: hd(after_agent.routes)}]
    assert diff.routes.order == %{before: ["run"], after: ["run", "new"]}
    assert diff.agents.added == after_agent.topology.agents
    assert diff.extensions.added == after_agent.extensions
    assert diff.state == %{before: before.state, after: after_agent.state}
    refute Diff.changed?(diff, :connections)
    assert Diff.empty?(%Diff{})
    assert Diff.empty?(Diff.between(before, before))
  end

  test "Flow and module handler updates run through the same route boundary" do
    assert {:ok, agent, _} = Agent.mutate(F.agent(), [D.route_update("run", %{handler: F.Flow})])
    assert hd(agent.routes).handler == %{kind: :flow, target: F.Flow}
    assert {:ok, ^agent, []} = Agent.cmd(agent, F.signal([]))
  end

  test "definition Plugin edits add no state and remove needs no state discard" do
    original = Agent.definition(F.agent())
    assert {:ok, added, diff} = Agent.mutate(original, [D.plugin_add(F.Counter)])
    assert added.state == nil and diff.state == nil
    assert {:ok, instance} = Agent.instantiate(added, id: "defined-plugin")
    assert instance.state.counter == 3
    assert {:ok, ^original, _} = Agent.mutate(added, [D.plugin_remove(F.Counter)])
  end

  test "malformed set values cannot crash later edits" do
    for batch <- [
          [D.topology_set(%{agents: [%{}]}), D.agent_remove(:missing)],
          [
            D.topology_set(%{connections: [%{path: "x"}]}),
            D.connection_remove("x", from: :root, to: :root)
          ],
          [D.routes_set([%{}]), D.route_remove("run")],
          [D.routes_reorder(["run" | :bad])],
          [D.agent_add(:a, F.Worker, initial_state: %{pid: self()})],
          [D.route_update("run", %{defaults: %{fun: fn -> :ok end}})]
        ] do
      assert {:error, _} = Agent.mutate(F.agent(), batch)
    end
  end

  test "Plugin changes reject owned directives even when configuration edits cancel" do
    assert {:ok, agent, _} = Agent.mutate(F.agent(), [D.plugin_add(F.Counter)])
    batch = [D.plugin_configure(F.Counter, []), %F.Owned{}]

    assert {:error, %{code: :plugin_change_with_owned_directive}} =
             Agent.cmd(agent, F.signal(batch))

    assert agent.state.counter == 3

    assert {:error, :migration_failed} =
             Agent.mutate(agent, [
               D.plugin_configure(F.Counter, [], migrate: {F.Migrations, :fail, []})
             ])
  end

  test "state validation does not fill missing nested defaults during a transition" do
    definition =
      Agent.define!(%{
        name: "nested",
        schema:
          Zoi.object(%{
            nested: Zoi.object(%{value: Zoi.integer() |> Zoi.default(1)}) |> Zoi.default(%{})
          })
      })

    agent = Agent.instantiate!(definition, id: "nested")
    assert {:error, %{code: :incomplete_state}} = Agent.transition(agent, %{nested: %{}})
    assert {:ok, ^agent} = Agent.transition(agent, agent.state)
  end

  test "runtime constructors have a separate noun_verb API" do
    alias Jido.AgentServer.Directive, as: R
    signal = Jido.Signal.new!("event", %{}, source: "/test")

    for directive <- [
          R.agent_start(F.Worker, :worker),
          R.agent_stop(:worker),
          R.server_stop(),
          R.process_start({Elixir.Agent, fn -> 0 end}),
          R.error_report(:failed),
          R.signal_send(signal, self(), timeout: 100),
          R.owner_send(signal),
          R.agent_send(:worker, signal)
        ] do
      assert {:ok, ^directive} = D.validate(directive)
      refute Agent.Mutation.mutation?(directive)
    end

    refute function_exported?(D, :spawn_child, 2)
    refute function_exported?(D, :topology_add, 2)
    refute function_exported?(D, :stop, 0)
    refute function_exported?(R, :agent_attach, 2)
    refute function_exported?(R, :agent_attach, 3)

    for name <-
          ~w(AdoptChild SpawnChild StopChild SpawnProcess Stop Error EmitToParent EmitToChild) do
      refute Code.ensure_loaded?(Module.concat(D, name))
    end

    refute Code.ensure_loaded?(Module.concat(Agent, "Source"))

    assert %R.AgentStart{name: :worker} = R.agent_start(F.Worker, :worker)
    assert %R.AgentStop{name: :worker} = R.agent_stop(:worker)
    assert %R.AgentSend{name: :worker} = R.agent_send(:worker, signal)
  end

  test "topology replacement rejects duplicate connection identities with different delivery" do
    assert {:ok, agent, _} =
             Agent.mutate(F.agent(), [
               D.agent_add(:a, F.Worker),
               D.connection_add("work", from: :root, to: :a)
             ])

    edge = hd(agent.topology.connections)
    topology = %{agent.topology | connections: [edge, %{edge | delivery: :broadcast}]}
    assert {:error, %{code: :duplicate}} = Agent.mutate(agent, [D.topology_set(topology)])
  end

  test "Diff reports top-level definition changes made by a full upgrade" do
    before = F.agent()
    schema = Zoi.object(%{count: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0)})
    upgraded = %{before | schema: schema, vsn: 2, metadata: %{source: "upgrade"}}
    assert {:ok, ^upgraded} = Agent.validate(upgraded)
    diff = Diff.between(before, upgraded)

    assert diff.fields == %{
             schema: %{before: before.schema, after: schema},
             vsn: %{before: 1, after: 2},
             metadata: %{before: %{}, after: %{source: "upgrade"}}
           }

    assert Diff.changed?(diff, :fields)
    refute Diff.empty?(diff)
    refute Diff.changed?(diff, :state)
    refute Diff.changed?(diff, :routes)
  end
end
