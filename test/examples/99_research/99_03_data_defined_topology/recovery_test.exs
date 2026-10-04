defmodule JidoTest.Examples.Research.DataTopologyRecoveryTest do
  use JidoTest.Case, async: true
  @moduletag :example
  import JidoTest.DataTopologyAssertions
  import JidoTest.TopologyAssertions

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Research.DataDefinedTopology, as: Example
  alias Jido.Examples.Research.DataDefinedTopology.{Definitions, Recovery, Worker}
  alias Jido.Signal.Bus
  alias Jido.Topology
  alias Jido.Topology.Controller

  for member_form <- [:module, :json] do
    test "OTP member restart retains the selected #{member_form} definition and committed state",
         c do
      source = source(unquote(member_form))
      assert {:ok, definition} = Recovery.definition(source)
      assert {:ok, instance} = Topology.instantiate(definition, id: unique_id("member-recovery"))

      controller =
        start_supervised!({Controller, jido: c.jido, topology: instance, repair: :manual})

      assert :ok = Controller.await_ready(controller)

      try do
        server = Controller.whereis_agent(controller, :worker)
        assert {:ok, committed} = Example.record(server, Definitions.path(source), 5)
        kill(server)
        assert :ok = Controller.await_ready(controller)
        replacement = Controller.whereis_agent(controller, :worker)
        assert is_pid(replacement)
        assert replacement != server
        assert Server.agent(replacement) == committed
        assert Server.snapshot(replacement).state_version == 1
        assert_selected(replacement, source)
      after
        stop_plan(controller, c.jido, instance, [Controller.whereis_bus(controller, :events)])
      end
    end

    test "manual Bus repair preserves the selected #{member_form} definition and Agent PID", c do
      source = source(unquote(member_form))
      assert {:ok, definition} = Recovery.definition(source)
      assert {:ok, instance} = Topology.instantiate(definition, id: unique_id("bus-recovery"))

      controller =
        start_supervised!({Controller, jido: c.jido, topology: instance, repair: :manual})

      assert :ok = Controller.await_ready(controller)

      try do
        server = Controller.whereis_agent(controller, :worker)
        bus = Controller.whereis_bus(controller, :events)
        assert {:ok, committed} = Example.record(server, Definitions.path(source), 5)
        kill(bus)
        assert :ok = Controller.reconcile(controller)
        assert :ok = Controller.await_ready(controller)
        assert Controller.whereis_bus(controller, :events) != bus
        assert Controller.whereis_agent(controller, :worker) == server
        assert Server.agent(server) == committed
        assert_selected(server, source)
        publish_record(controller, source)
        eventually(fn -> Server.agent(server).state.total == 8 end)
      after
        stop_plan(controller, c.jido, instance, [Controller.whereis_bus(controller, :events)])
      end
    end

    test "Jido and Controller restart restore the selected #{member_form} definition from persistence",
         c do
      source = source(unquote(member_form))
      assert {:ok, definition} = Recovery.definition(source)
      assert {:ok, instance} = Topology.instantiate(definition, id: unique_id("durable-recovery"))
      durable = :"data_topology_durable_#{c.jido}"
      namespace = Atom.to_string(durable)

      opts = [
        name: durable,
        namespace: namespace,
        persistence: {Jido.Persistence.ETS, table: durable}
      ]

      start_supervised!({Jido, opts}, id: durable)
      controller = start_supervised!({Controller, jido: durable, topology: instance})
      assert :ok = Controller.await_ready(controller)
      server = Controller.whereis_agent(controller, :worker)
      bus = Controller.whereis_bus(controller, :events)
      assert {:ok, committed} = Example.record(server, Definitions.path(source), 5)
      monitors = monitor_runtime([server], [bus])
      stop_supervised!({Controller, instance.id})
      assert_down(monitors)
      stop_supervised!(durable)

      # The same namespace and store survive loss of the named Jido instance.
      # No local runtime checkpoint is available to this replacement tree.
      start_supervised!({Jido, opts}, id: durable)
      controller = start_supervised!({Controller, jido: durable, topology: instance})

      try do
        assert :ok = Controller.await_ready(controller)
        replacement = Controller.whereis_agent(controller, :worker)
        assert replacement != server
        assert Server.agent(replacement) == committed
        assert Server.snapshot(replacement).state_version == 1
        assert_selected(replacement, source)
        publish_record(controller, source)
        eventually(fn -> Server.agent(replacement).state.total == 8 end)
        assert Server.agent(replacement).state.records == 2
      after
        stop_plan(controller, durable, instance, [Controller.whereis_bus(controller, :events)])
      end
    end
  end

  defp source(:module), do: Worker

  defp source(:json) do
    assert {:ok, source} = Definitions.stored(:alice)
    source
  end

  defp publish_record(controller, source) do
    signal =
      Jido.Signal.new!(Definitions.path(source), %{value: 1},
        source: "/examples/research/data_defined_topology"
      )

    assert {:ok, [_]} = Bus.publish(Controller.whereis_bus(controller, :events), [signal])
  end

  defp kill(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 5_000
  end
end
