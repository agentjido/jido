defmodule JidoTest.Contract.PluginAuditApiTest do
  use Covenant.Case, component: "jido.plugin.audit", async: true

  alias Jido.Plugin.Audit
  alias Jido.Plugin.Audit.Record

  @tag obligation: ["jido.plugin.audit.I1", "jido.plugin.audit.I2"]
  test "Audit exposes only record construction and Record validation" do
    assert documented_api(Audit) == [{:function, :record, 3}]
    assert documented_types(Audit) == [{:type, :plugin_option, 0}, {:type, :record_option, 0}]

    assert documented_api(Record) == [{:function, :validate, 1}]
    assert documented_types(Record) == [{:type, :t, 0}]

    assert public_module?(Audit)
    assert public_module?(Record)
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
