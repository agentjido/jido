defmodule JidoTest.Examples.Research.DataTopologyAdditionsTest do
  use JidoTest.Case, async: true
  @moduletag :example
  import JidoTest.DataTopologyAssertions

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Research.DataDefinedTopology, as: Example
  alias Jido.Examples.Research.DataDefinedTopology.{Observer, Startup}
  alias Jido.Examples.Research.DataDefinedTopology.Topology, as: DSLTopology
  alias Jido.Topology
  alias Jido.Topology.Controller

  for topology_form <- [:dsl, :data], member_form <- [:module, :json] do
    test "a running #{topology_form} Topology adds three #{member_form} members", c do
      initial_definition = initial_definition(unquote(topology_form))

      assert {:ok, initial} =
               Topology.instantiate(initial_definition, id: unique_id("added-members"))

      controller =
        start_supervised!({Controller, jido: c.jido, topology: initial, repair: :manual})

      assert :ok = Controller.await_ready(controller)
      observer = Controller.whereis_agent(controller, :observer)

      try do
        assert {:ok, committed} =
                 Example.record(
                   observer,
                   "examples.research.data_defined_topology.observer.record",
                   7
                 )

        entries = entries(unquote(member_form))
        assert {:ok, expanded} = Startup.add_members(initial, entries)
        assert :ok = Controller.update(controller, expanded)
        assert :ok = Controller.await_ready(controller)
        assert Controller.whereis_agent(controller, :observer) == observer
        assert Server.agent(observer) == committed
        assert_started(c.jido, expanded, entries)
        assert_executed(c.jido, expanded, entries)
        assert Jido.agent_count(c.jido) == 4
      after
        # The expanded target can fail before it exists. Query stable member
        # identities for cleanup in both the current and future implementations.
        pids =
          for key <- [:observer, :alice, :bob, :charlie],
              pid = Controller.whereis_agent(controller, key),
              is_pid(pid),
              do: pid

        JidoTest.TopologyAssertions.stop_topology(controller, pids)
        assert Jido.agent_count(c.jido) == 0
      end
    end
  end

  defp initial_definition(:dsl), do: DSLTopology.topology()

  defp initial_definition(:data),
    do:
      Topology.new!(
        name: "hybrid_data_defined_topology",
        agents: [%{key: :observer, module: Observer}]
      )

  defp entries(:module), do: Startup.module_entries()

  defp entries(:json) do
    assert {:ok, entries} = Startup.data_entries(:json)
    entries
  end
end
