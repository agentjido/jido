defmodule JidoTest.AgentServer.Composition.ApiTest do
  use Covenant.Case, component: "jido.agent_server.composition", async: true

  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.{CompositionRuntime, TopologyBus, TopologyRuntime}

  @tag obligation: "jido.agent_server.composition.I10"
  test "composition stays on the typed AgentServer facade" do
    public_api = MapSet.new(documented_api(Server))

    assert MapSet.subset?(
             MapSet.new([
               {:function, :adopt_child, 4},
               {:function, :children, 2},
               {:function, :members, 3},
               {:function, :spawn_child, 4},
               {:function, :stop_child, 3}
             ]),
             public_api
           )

    public_types = MapSet.new(documented_types(Server))

    assert MapSet.subset?(
             MapSet.new([
               {:type, :adoption_option, 0},
               {:type, :child_info, 0},
               {:type, :child_option, 0},
               {:type, :child_tag, 0}
             ]),
             public_types
           )

    for module <- [CompositionRuntime, TopologyBus, TopologyRuntime] do
      refute public_module?(module)
    end
  end

  defp documented_api(module) do
    module
    |> docs()
    |> Enum.flat_map(fn
      {{kind, name, arity}, _, _, doc, _}
      when kind in [:function, :macro] and doc not in [:hidden, :none] ->
        [{kind, name, arity}]

      _other ->
        []
    end)
    |> Enum.sort()
  end

  defp documented_types(module) do
    module
    |> docs()
    |> Enum.flat_map(fn
      {{:type, name, arity}, _, _, doc, _} when doc not in [:hidden, :none] ->
        [{:type, name, arity}]

      _other ->
        []
    end)
    |> Enum.sort()
  end

  defp docs(module) do
    {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(module)
    docs
  end

  defp public_module?(module) do
    {:docs_v1, _, _, _, module_doc, _, _} = Code.fetch_docs(module)
    module_doc not in [:hidden, :none]
  end
end
