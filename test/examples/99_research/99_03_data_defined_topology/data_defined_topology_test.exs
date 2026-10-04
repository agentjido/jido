defmodule JidoTest.Examples.Research.DataDefinedTopologyTest do
  use JidoTest.Case, async: true

  @moduletag :example

  import JidoTest.TopologyAssertions

  alias Jido.Agent
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Research.DataDefinedTopology, as: Example
  alias Jido.Examples.Research.DataDefinedTopology.Observer
  alias Jido.Examples.Research.DataDefinedTopology.Topology, as: HybridTopology
  alias Jido.Topology.Controller

  @observer_record "examples.research.data_defined_topology.observer.record"
  @alice_record "examples.research.data_defined_topology.alice.record"

  test "a valid stored Agent fails a DSL topology update and preserves the live member", c do
    {:ok, initial} = Example.initial(unique_id("data-topology-boundary"))
    assert initial.definition == HybridTopology.topology()
    controller = start_supervised!({Controller, jido: c.jido, topology: initial})
    assert :ok = Controller.await_ready(controller)
    observer = Controller.whereis_agent(controller, :observer)

    try do
      assert {:ok, committed} = Example.record(observer, @observer_record, 7)
      assert {:ok, alice} = Example.stored_alice()
      assert Agent.definition?(alice)
      assert alice.module == Agent
      assert {:ok, instance} = Agent.instantiate(alice, id: "standalone", state: %{total: 2})
      assert instance.state == %{label: "Alice", total: 2}

      # The Agent runtime accepts the same decoded definition.
      assert {:ok, standalone} =
               Jido.start_agent(c.jido, alice,
                 id: unique_id("standalone-alice"),
                 initial_state: %{total: 2}
               )

      assert {:ok, %{state: %{label: "Alice", total: 5}}} =
               Example.record(standalone, @alice_record, 3)

      ref = Process.monitor(standalone)
      assert :ok = Jido.stop_agent(c.jido, Server.agent(standalone).id)
      assert_receive {:DOWN, ^ref, :process, ^standalone, _}, 5_000

      assert {:error, %Jido.Error.ValidationError{message: "Expected an Agent module"}} =
               Example.expanded(initial, alice)

      assert :ok = Controller.await_ready(controller)
      assert Controller.whereis_agent(controller, :observer) == observer
      assert Controller.whereis_agent(controller, :alice) == nil
      assert Server.agent(observer) == committed
      assert Jido.agent_count(c.jido) == 1
    after
      stop_topology(controller, [observer])
      assert Jido.agent_count(c.jido) == 0
    end
  end

  test "a data-defined Agent can join a ready DSL topology without replacing its existing member",
       c do
    {:ok, initial} = Example.initial(unique_id("data-topology-addition"))
    assert initial.definition == HybridTopology.topology()
    controller = start_supervised!({Controller, jido: c.jido, topology: initial})
    assert :ok = Controller.await_ready(controller)
    observer = Controller.whereis_agent(controller, :observer)

    try do
      assert {:ok, committed} = Example.record(observer, @observer_record, 7)
      assert {:ok, definition} = Example.stored_alice()

      # This assertion records the desired contract. It must fail before the
      # core fix. Target construction fails before Controller.update/3 runs.
      assert {:ok, expanded} = Example.expanded(initial, definition)
      assert :ok = Controller.update(controller, expanded)
      assert :ok = Controller.await_ready(controller)

      alice = Controller.whereis_agent(controller, :alice)
      assert is_pid(alice)
      assert Controller.whereis_agent(controller, :observer) == observer
      assert Server.agent(observer) == committed

      actual = Server.agent(alice)
      assert actual.module == definition.module
      assert actual.schema == definition.schema
      assert actual.routes == definition.routes
      assert actual.metadata["document_id"] == "agents/alice"
      assert actual.metadata["jido.topology"] == %{id: initial.id, key: "agent/alice"}
      assert actual.state == %{label: "Alice", total: 2}

      assert {:ok, %{state: %{label: "Alice", total: 5}}} =
               Example.record(alice, @alice_record, 3)

      assert Jido.agent_count(c.jido) == 2
    after
      members = [observer, Controller.whereis_agent(controller, :alice)] |> Enum.filter(&is_pid/1)
      stop_topology(controller, members)
      assert Jido.agent_count(c.jido) == 0
    end
  end

  test "a module-defined Agent can join the same DSL topology", c do
    {:ok, initial} = HybridTopology.new(id: unique_id("hybrid-module-addition"))
    controller = start_supervised!({Controller, jido: c.jido, topology: initial})
    assert :ok = Controller.await_ready(controller)
    observer = Controller.whereis_agent(controller, :observer)

    try do
      assert {:ok, committed} = Example.record(observer, @observer_record, 7)
      assert {:ok, target} = Example.expanded(initial, Observer)
      assert :ok = Controller.update(controller, target)
      assert :ok = Controller.await_ready(controller)

      added = Controller.whereis_agent(controller, :alice)
      assert is_pid(added)
      assert Server.agent(added).state.total == 2
      assert Controller.whereis_agent(controller, :observer) == observer
      assert Server.agent(observer) == committed
      assert HybridTopology.topology() == initial.definition
      assert Jido.agent_count(c.jido) == 2
    after
      members = [observer, Controller.whereis_agent(controller, :alice)] |> Enum.filter(&is_pid/1)
      stop_topology(controller, members)
      assert Jido.agent_count(c.jido) == 0
    end
  end
end
