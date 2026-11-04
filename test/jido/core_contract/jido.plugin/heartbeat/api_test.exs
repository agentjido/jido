defmodule JidoTest.Contract.PluginHeartbeatApiTest do
  use Covenant.Case, component: "jido.plugin.heartbeat", async: true

  import Jido.Test.PublicAPI

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
end
