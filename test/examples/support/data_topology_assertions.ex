defmodule JidoTest.DataTopologyAssertions do
  @moduledoc false
  import ExUnit.Assertions
  import JidoTest.TopologyAssertions

  alias Jido.AgentServer
  alias Jido.Examples.Research.DataDefinedTopology, as: Example
  alias Jido.Examples.Research.DataDefinedTopology.Definitions

  def assert_selected(server, source) when is_atom(source),
    do: assert_selected(server, source.definition())

  def assert_selected(server, definition) do
    actual = AgentServer.agent(server)
    fields = [:module, :name, :description, :schema, :routes]
    assert Map.take(actual, fields) == Map.take(definition, fields)
    assert Enum.take(actual.plugins, length(definition.plugins)) == definition.plugins
    assert Map.delete(actual.metadata, "jido.topology") == definition.metadata
    actual
  end

  def assert_started(jido, instance, entries) do
    for entry <- entries do
      spec = Map.fetch!(instance.plan.agents, "agent/#{entry.key}")
      server = Jido.whereis_agent(jido, spec.id)
      assert is_pid(server)
      actual = assert_selected(server, entry.module)
      assert actual.id == spec.id
      assert actual.state.total == entry.initial_state.total
      assert actual.metadata["jido.topology"] == %{id: instance.id, key: spec.key}
    end
  end

  def assert_executed(jido, instance, entries) do
    for entry <- entries do
      spec = Map.fetch!(instance.plan.agents, "agent/#{entry.key}")
      server = Jido.whereis_agent(jido, spec.id)
      assert {:ok, committed} = Example.record(server, Definitions.path(entry.module), 5)
      assert committed.state.total == entry.initial_state.total + 5
      actual = assert_selected(server, entry.module)

      if actual.plugins == [],
        do: refute(Map.has_key?(committed.state, :records)),
        else: assert(committed.state.records == 1)
    end
  end

  def stop_plan(controller, jido, instance, resources \\ []) do
    agents =
      for {_, spec} <- instance.plan.agents,
          pid = Jido.whereis_agent(jido, spec.id),
          is_pid(pid),
          do: pid

    stop_topology(controller, agents, Enum.filter(resources, &is_pid/1))
    assert Jido.agent_count(jido) == 0
  end
end
