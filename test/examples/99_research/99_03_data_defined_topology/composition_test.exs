defmodule JidoTest.Examples.Research.DataTopologyCompositionTest do
  use JidoTest.Case, async: true
  @moduletag :example
  import JidoTest.DataTopologyAssertions

  alias Jido.Examples.Research.DataDefinedTopology, as: Example
  alias Jido.Examples.Research.DataDefinedTopology.{Composition, Definitions, Worker}
  alias Jido.Topology
  alias Jido.Topology.{Controller, Ref}

  for parent_form <- [:dsl, :data],
      child_form <- [:dsl, :data],
      member_form <- [:module, :json] do
    test "#{parent_form} parent includes #{child_form} child with #{member_form} Agent", c do
      source = source(unquote(member_form))
      child = child(unquote(child_form), unquote(member_form), source)
      assert {:ok, definition} = Composition.parent(unquote(parent_form), child)
      assert {:ok, instance} = Topology.instantiate(definition, id: unique_id("composed-members"))
      controller = start_supervised!({Controller, jido: c.jido, topology: instance})

      try do
        assert :ok = Controller.await_ready(controller)
        server = Controller.whereis_agent(controller, Ref.ref(:team, :worker))
        actual = assert_selected(server, source)
        assert actual.id == instance.id <> "/component/team/agent/worker"

        assert actual.metadata["jido.topology"] == %{
                 id: instance.id,
                 key: "component/team/agent/worker"
               }

        assert {:ok, %{state: %{total: 7}}} = Example.record(server, Definitions.path(source), 5)
      after
        stop_plan(controller, c.jido, instance)
      end
    end
  end

  defp source(:module), do: Worker

  defp source(:json) do
    assert {:ok, source} = Definitions.stored(:alice)
    source
  end

  defp child(:dsl, :module, _source), do: Composition.dsl_child()

  defp child(form, _member_form, source) do
    assert {:ok, child} = Composition.child(form, source)
    child
  end
end
