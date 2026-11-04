defmodule JidoTest.Contract.PluginAuditApiTest do
  use Covenant.Case, component: "jido.plugin.audit", async: true

  import Jido.Test.PublicAPI

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
end
