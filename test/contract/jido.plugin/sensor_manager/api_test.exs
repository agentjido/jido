defmodule JidoTest.Contract.PluginSensorManagerApiTest do
  use Covenant.Case, component: "jido.plugin.sensor_manager", async: true

  alias Jido.Plugin.SensorManager
  alias Jido.Plugin.SensorManager.{Init, Start, Stop}

  @tag obligation: ["jido.plugin.sensor_manager.I1", "jido.plugin.sensor_manager.I3"]
  test "Sensor Manager exposes only its constructors, Directives, option, and sensor Init" do
    assert_public(SensorManager,
      api: [{:function, :start, 3}, {:function, :stop, 1}],
      types: [{:type, :option, 0}]
    )

    for module <- [Start, Stop] do
      assert_public(module, api: [{:function, :validate, 1}], types: [{:type, :t, 0}])
    end

    assert_public(Init,
      api: [{:function, :schema, 0}],
      types: [{:type, :t, 0}]
    )

    for module <- [
          SensorManager.Agent,
          SensorManager.Runtime,
          SensorManager.Runtime.Controller,
          SensorManager.Server
        ] do
      refute public_module?(module)
    end
  end

  defp assert_public(module, expected) do
    assert public_module?(module)
    assert documented_api(module) == Keyword.fetch!(expected, :api)
    assert documented_types(module) == Keyword.fetch!(expected, :types)
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
