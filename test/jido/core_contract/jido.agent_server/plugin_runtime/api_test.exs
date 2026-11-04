defmodule JidoTest.AgentServer.PluginRuntime.ApiTest do
  use Covenant.Case, component: "jido.agent_server.plugin_runtime", async: true

  import Jido.Test.PublicAPI

  alias Jido.AgentServer.Plugin, as: Runtime
  alias Jido.AgentServer.Plugin.Callbacks
  alias Jido.Plugin.Spec.Runtime, as: RuntimeSpec

  @tag obligation: "jido.agent_server.plugin_runtime.I13"
  test "the live Plugin API exposes only its state owner" do
    assert {:function, :state, 2} in documented_api(Runtime)
    assert public_module?(Runtime)

    for module <- [Callbacks, RuntimeSpec] do
      refute public_module?(module)
    end
  end
end
