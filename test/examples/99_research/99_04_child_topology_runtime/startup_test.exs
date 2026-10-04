defmodule JidoTest.Examples.Research.ChildTopologyStartupTest do
  use JidoTest.Case, async: true
  @moduletag :example
  import JidoTest.ChildTopologyRuntimeAssertions

  alias Jido.AgentServer
  alias Jido.Examples.Research.ChildTopologyRuntime.{Child, Parent, Specifications}
  alias Jido.Topology
  alias Jido.Topology.Controller

  test "a combined DSL Topology provides one supervised runtime child" do
    module = Parent
    assert Code.ensure_loaded?(module)
    assert function_exported?(module, :child_spec, 1)
    spec = apply(module, :child_spec, [[jido: :example_jido, id: "parent", activation: :lazy]])
    assert spec.type == :supervisor
    assert {runtime_module, :start_link, [_]} = spec.start
    assert runtime_module == runtime()
  end

  test "the proposed stored child members already run alone", c do
    for entry <- Specifications.data_entries() do
      assert {:ok, server} =
               Jido.start_agent(c.jido, entry.definition,
                 id: unique_id("stored-child-control"),
                 initial_state: entry.initial_state
               )

      try do
        assert {:ok, committed} = AgentServer.call(server, record())
        assert committed.state.total == 1
        assert committed.state.label == entry.initial_state.label
        assert committed.schema == entry.definition.schema
        assert committed.routes == entry.definition.routes
        assert committed.metadata == entry.definition.metadata
      after
        ref = Process.monitor(server)
        assert :ok = Jido.stop_agent(c.jido, AgentServer.agent(server).id)
        assert_receive {:DOWN, ^ref, :process, ^server, _}, 5_000
      end
    end

    assert Jido.agent_count(c.jido) == 0
  end

  for parent_form <- [:dsl, :data], child_form <- [:dsl, :data, :data_agents] do
    test "#{parent_form} parent lazily owns a #{child_form} child runtime", c do
      assert {:ok, definition} = Specifications.parent(unquote(parent_form), unquote(child_form))
      id = unique_id("parent")
      parent = start_supervised!({runtime(), opts(c.jido, id, definition)})

      try do
        assert :ok = rpc(:await_ready, [c.jido, id, 5_000])
        assert is_pid(rpc(:director, [c.jido, id]))
        assert is_pid(rpc(:controller, [c.jido, id]))
        assert rpc(:whereis_child, [c.jido, id, :team]) == nil

        assert %{children: %{"team" => %{id: child, status: :dormant}}} =
                 rpc(:status, [c.jido, id])

        assert child == child_id(id)
        assert {:ok, %{state: %{total: 5}}} = call_child(c.jido, id, 5)

        child_runtime = rpc(:whereis_child, [c.jido, id, :team])
        assert is_pid(child_runtime)
        assert child_runtime != parent
        assert rpc(:controller, [c.jido, child]) != rpc(:controller, [c.jido, id])
        assert rpc(:director, [c.jido, child]) != rpc(:director, [c.jido, id])
        assert is_pid(rpc(:whereis_bus, [c.jido, child, :signals]))
        alice = rpc(:whereis_member, [c.jido, child, :alice])
        assert is_pid(alice)
        assert rpc(:whereis_member, [c.jido, child, :bob]) == nil
        assert rpc(:whereis_member, [c.jido, id, :alice]) == nil
        assert %{active_members: 1, dormant_members: 1} = rpc(:status, [c.jido, child])
        assert :ok = rpc(:await_ready, [c.jido, child, 5_000])
        assert {:ok, %{state: %{total: 7}}} = call_child(c.jido, id, 2)
        assert rpc(:whereis_member, [c.jido, child, :alice]) == alice

        if unquote(child_form) == :data_agents do
          actual = AgentServer.agent(alice)
          assert actual.name == "alice"
          assert actual.metadata["document_id"] == "child/alice"
        end
      after
        stop_runtime(c.jido, id, parent)
      end
    end
  end

  test "static include flattens the child into one eager Controller target", c do
    assert {:ok, definition} =
             Topology.new(name: "static-parent", includes: [%{key: :team, topology: Child}])

    assert {:ok, instance} = Topology.instantiate(definition, id: unique_id("static-parent"))
    assert map_size(instance.plan.agents) == 2
    controller = start_supervised!({Controller, jido: c.jido, topology: instance})

    try do
      assert :ok = Controller.await_ready(controller)
      alice = Controller.whereis_agent(controller, Topology.Ref.ref(:team, :alice))
      bob = Controller.whereis_agent(controller, Topology.Ref.ref(:team, :bob))
      assert is_pid(alice)
      assert is_pid(bob)
      assert is_pid(Controller.whereis_bus(controller, Topology.Ref.ref(:team, :signals)))
      assert Jido.agent_count(c.jido) == 2
      # An included combined module does not start its own director or Controller.
      assert Jido.whereis_agent(c.jido, instance.id <> "/child/team/director") == nil
    after
      JidoTest.DataTopologyAssertions.stop_plan(controller, c.jido, instance, [
        Controller.whereis_bus(controller, Topology.Ref.ref(:team, :signals))
      ])
    end
  end

  for activation <- [:eager, :deferred] do
    test "a standalone #{activation} runtime owns its director and full target", c do
      id = unique_id("activation-mode")

      options =
        opts(c.jido, id, Child,
          director: Child.owner(),
          activation: unquote(activation)
        )

      parent = start_supervised!({runtime(), options})

      try do
        assert :ok = rpc(:await_ready, [c.jido, id, 5_000])
        assert is_pid(rpc(:director, [c.jido, id]))

        if unquote(activation) == :deferred do
          assert %{active_members: 0, dormant_members: 2} = rpc(:status, [c.jido, id])
          assert rpc(:whereis_member, [c.jido, id, :alice]) == nil
          assert rpc(:whereis_member, [c.jido, id, :bob]) == nil
          assert :ok = rpc(:activate, [c.jido, id, :all])
          assert :ok = rpc(:await_ready, [c.jido, id, 5_000])
        end

        assert is_pid(rpc(:whereis_member, [c.jido, id, :alice]))
        assert is_pid(rpc(:whereis_member, [c.jido, id, :bob]))
        assert is_pid(rpc(:whereis_bus, [c.jido, id, :signals]))
        assert Jido.agent_count(c.jido) == 3
      after
        stop_runtime(c.jido, id, parent)
      end
    end
  end
end
