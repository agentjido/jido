defmodule JidoTest.Examples.Research.DataTopologyGroupsTest do
  use JidoTest.Case, async: true
  @moduletag :example
  import JidoTest.DataTopologyAssertions

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Research.DataDefinedTopology, as: Example
  alias Jido.Examples.Research.DataDefinedTopology.{Definitions, Groups, Worker}
  alias Jido.Topology
  alias Jido.Topology.Controller

  for kind <- [:counted, :keyed],
      topology_form <- [:dsl, :data],
      member_form <- [:module, :json] do
    test "#{topology_form} #{kind} group expands a #{member_form} Agent source", c do
      source = source(unquote(member_form))
      assert {:ok, definition} = Groups.definition(unquote(kind), source, unquote(topology_form))
      input = Groups.input(unquote(kind))

      assert {:ok, instance} =
               Topology.instantiate(definition, id: unique_id("group-members"), input: input)

      controller = start_supervised!({Controller, jido: c.jido, topology: instance})

      try do
        assert :ok = Controller.await_ready(controller)

        for {key, total, label} <- expected_members(unquote(kind)) do
          server = Controller.whereis_agent(controller, :workers, key)
          assert is_pid(server)
          actual = assert_selected(server, source)
          assert actual.state.total == total
          if label, do: assert(actual.state.label == label)
          assert {:ok, committed} = Example.record(server, Definitions.path(source), 3)
          assert committed.state.total == total + 3
          assert committed.state.records == 1
        end

        assert_keyed_identity(unquote(kind), definition, instance, input, controller)
      after
        stop_plan(controller, c.jido, instance)
      end
    end
  end

  for member_form <- [:module, :json] do
    test "a #{member_form} group validates each resolved member state before activation", c do
      assert {:ok, definition} = Groups.definition(:keyed, source(unquote(member_form)), :data)
      input = %{members: [%{key: "bad", label: "Bad", initial: "invalid"}]}

      assert {:error, %Jido.Error.ValidationError{}} =
               Topology.instantiate(definition,
                 id: unique_id("invalid-group-state"),
                 input: input
               )

      assert Jido.agent_count(c.jido) == 0
    end
  end

  defp assert_keyed_identity(:counted, _definition, _instance, _input, _controller), do: :ok

  defp assert_keyed_identity(:keyed, definition, instance, %{members: members}, controller) do
    # Reordering input records must not change keyed identity or the plan.
    assert {:ok, reordered} =
             Topology.instantiate(definition,
               id: instance.id,
               input: %{members: Enum.reverse(members)}
             )

    assert reordered.plan == instance.plan
    east = Controller.whereis_agent(controller, :workers, "east/one")
    assert Server.agent(east).id == instance.id <> "/group/workers/east%2Fone"
  end

  defp source(:module), do: Worker

  defp source(:json) do
    assert {:ok, source} = Definitions.stored(:alice)
    source
  end

  defp expected_members(:counted), do: [{1, 1, nil}, {2, 2, nil}, {3, 3, nil}]
  defp expected_members(:keyed), do: [{"east/one", 2, "East"}, {"west", 5, "West"}]
end
