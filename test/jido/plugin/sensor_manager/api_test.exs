defmodule Jido.Plugin.SensorManager.ApiTest do
  use Covenant.Case, component: "jido.plugin.sensor_manager", async: true

  import Jido.Test.PublicAPI

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

    for module <- [SensorManager.Runtime, SensorManager.Runtime.Controller] do
      refute public_module?(module)
    end

    refute Code.ensure_loaded?(SensorManager.Agent)
    refute Code.ensure_loaded?(SensorManager.Server)
  end

  defp assert_public(module, expected) do
    assert public_module?(module)
    assert documented_api(module) == Keyword.fetch!(expected, :api)
    assert documented_types(module) == Keyword.fetch!(expected, :types)
  end
end
