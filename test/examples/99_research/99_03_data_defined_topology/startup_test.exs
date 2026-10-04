defmodule JidoTest.Examples.Research.DataTopologyStartupTest do
  use JidoTest.Case, async: true
  @moduletag :example

  import JidoTest.DataTopologyAssertions

  alias Jido.Agent
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Research.DataDefinedTopology, as: Example
  alias Jido.Examples.Research.DataDefinedTopology.{Definitions, Startup, Worker}
  alias Jido.Topology
  alias Jido.Topology.Controller

  for topology_form <- [:dsl, :data], member_form <- [:module, :dsl_value, :direct, :json] do
    test "#{topology_form} Topology starts three #{member_form} Agent members", c do
      entries = entries(unquote(member_form))
      assert {:ok, definition} = Startup.definition(unquote(topology_form), entries)
      assert {:ok, instance} = Topology.instantiate(definition, id: unique_id("initial-members"))
      controller = start_supervised!({Controller, jido: c.jido, topology: instance})

      try do
        assert :ok = Controller.await_ready(controller)
        assert_started(c.jido, instance, entries)
        assert_executed(c.jido, instance, entries)
        assert Jido.agent_count(c.jido) == 3
      after
        stop_plan(controller, c.jido, instance)
      end
    end
  end

  for topology_form <- [:dsl, :data] do
    test "#{topology_form} Topology starts mixed module and JSON Agent members", c do
      assert {:ok, entries} = Startup.mixed_entries(:json)
      assert {:ok, definition} = Startup.definition(unquote(topology_form), entries)
      assert {:ok, instance} = Topology.instantiate(definition, id: unique_id("mixed-members"))
      controller = start_supervised!({Controller, jido: c.jido, topology: instance})

      try do
        assert :ok = Controller.await_ready(controller)
        assert_started(c.jido, instance, entries)
        assert_executed(c.jido, instance, entries)
      after
        stop_plan(controller, c.jido, instance)
      end
    end
  end

  for form <- [:direct, :json] do
    test "#{form} Agent definitions share behavior but retain distinct schemas, routes, and Plugins",
         c do
      assert {:ok, entries} = Startup.data_entries(unquote(form))
      definitions = Enum.map(entries, &Definitions.source/1)
      assert Enum.uniq(Enum.map(definitions, & &1.module)) == [Worker]
      assert length(Enum.uniq(Enum.map(definitions, & &1.schema))) == 3
      assert length(Enum.uniq(Enum.map(definitions, & &1.routes))) == 3
      assert Enum.at(definitions, 1).plugins == []
      assert Enum.at(definitions, 0).plugins != []

      # Standalone execution is the control. Topology must preserve these same values.
      for {entry, index} <- Enum.with_index(entries) do
        assert Agent.definition?(Definitions.source(entry))

        assert {:ok, server} =
                 Jido.start_agent(c.jido, Definitions.source(entry),
                   id: unique_id("standalone"),
                   initial_state: entry.initial_state
                 )

        try do
          assert {:ok, committed} =
                   Example.record(server, Definitions.path(Definitions.source(entry)), 5)

          assert committed.state.total == entry.initial_state.total + 5
          assert_selected(server, Definitions.source(entry))

          if index == 1,
            do: refute(Map.has_key?(committed.state, :records)),
            else: assert(committed.state.records == 1)
        after
          ref = Process.monitor(server)
          assert :ok = Jido.stop_agent(c.jido, Server.agent(server).id)
          assert_receive {:DOWN, ^ref, :process, ^server, _}, 5_000
        end
      end

      assert Jido.agent_count(c.jido) == 0
    end
  end

  test "DSL and data Topologies produce the same module-based initial plan" do
    entries = Startup.module_entries()
    assert {:ok, from_dsl} = Startup.definition(:dsl, entries)
    assert {:ok, ^from_dsl} = Startup.definition(:data, entries)
    assert {:ok, instance} = Topology.instantiate(from_dsl, id: "same-authoring")
    assert {:ok, ^instance} = Startup.Topology.new(id: "same-authoring")
  end

  for member_form <- [:module, :direct] do
    test "invalid #{member_form} initial state fails planning before any member starts", c do
      source = if unquote(member_form) == :module, do: Worker, else: Definitions.direct(:alice)

      assert {:ok, definition} =
               Startup.definition(:data, [Definitions.entry(:alice, source, %{total: "bad"})])

      assert {:error, %Jido.Error.ValidationError{}} =
               Topology.instantiate(definition, id: unique_id("invalid-state"))

      assert Jido.agent_count(c.jido) == 0
    end
  end

  defp entries(:module), do: Startup.module_entries()

  defp entries(form) do
    assert {:ok, entries} = Startup.data_entries(form)
    entries
  end
end

defmodule JidoTest.Examples.Research.DirectDataMemberDSLTest do
  alias Jido.Examples.Research.DataDefinedTopology.Definitions
  use ExUnit.Case, async: false
  @moduletag :example

  test "the DSL definition selector accepts a neutral Agent definition" do
    path =
      Path.expand(
        "../../../../examples/99_research/99_03_data_defined_topology/fixtures/direct_dsl.exs",
        __DIR__
      )

    # The neutral definition selector keeps the compiled module form separate.
    Code.compile_file(path)
    module = Module.concat(Jido.Examples.Research.DataDefinedTopology, DirectDSL)
    assert {:ok, instance} = module.new(id: "direct-dsl")
    assert instance.plan.agents["agent/alice"]
    assert instance.plan.agents["group/workers/1"].definition == Definitions.direct(:bob)
    assert instance.plan.agents["group/workers/2"].definition == Definitions.direct(:bob)
  end
end
