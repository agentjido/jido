defmodule JidoTest.Contract.PluginBusApiTest do
  use Covenant.Case, component: "jido.plugin.bus", async: true

  alias Jido.Plugin.Bus
  alias Jido.Plugin.Bus.Client
  alias Jido.Plugin.Bus.Client.Runtime
  alias Jido.Plugin.Bus.Client.Server, as: ClientServer
  alias Jido.Plugin.Bus.DSL
  alias Jido.Plugin.Bus.DSL.References
  alias Jido.Plugin.Bus.Manager
  alias Jido.Plugin.Bus.Manager.Server, as: ManagerServer

  @tag obligation: ["jido.plugin.bus.I1", "jido.plugin.bus.I3", "jido.plugin.bus.I4"]
  test "Bus exposes only its Plugins, DSL, and Client option types" do
    for module <- [Bus, DSL, Manager, Client] do
      assert public_module?(module)
      assert documented_api(module) == []
    end

    assert documented_types(Bus) == []
    assert documented_types(DSL) == []
    assert documented_types(Manager) == []

    assert documented_types(Client) == [
             {:type, :option, 0},
             {:type, :start_position, 0}
           ]

    for module <- [References, Runtime, ClientServer, ManagerServer] do
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
