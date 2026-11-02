defmodule JidoTest.Contract.PluginHeartbeatApiTest do
  use Covenant.Case, component: "jido.plugin.heartbeat", async: true

  alias Jido.Plugin.Heartbeat
  alias Jido.Plugin.Heartbeat.Runtime
  alias Jido.Plugin.Heartbeat.Signal.Tick

  @tag obligation: [
         "jido.plugin.heartbeat.I1",
         "jido.plugin.heartbeat.I3",
         "jido.plugin.heartbeat.I4"
       ]
  test "Heartbeat exposes only its Plugin option type and default Tick Signal" do
    assert public_module?(Heartbeat)
    assert documented_api(Heartbeat) == []
    assert documented_types(Heartbeat) == [{:type, :option, 0}]

    assert public_module?(Tick)

    assert documented_api(Tick) == [
             {:function, :datacontenttype, 0},
             {:function, :dataschema, 0},
             {:function, :default_source, 0},
             {:function, :new, 2},
             {:function, :new!, 2},
             {:function, :schema, 0},
             {:function, :type, 0},
             {:function, :validate_data, 1}
           ]

    assert documented_types(Tick) == []
    refute public_module?(Runtime)
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
