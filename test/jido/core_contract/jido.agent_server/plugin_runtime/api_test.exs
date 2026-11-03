defmodule JidoTest.AgentServer.PluginRuntime.ApiTest do
  use Covenant.Case, component: "jido.agent_server.plugin_runtime", async: true

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

  defp docs(module) do
    {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(module)
    docs
  end

  defp public_module?(module) do
    {:docs_v1, _, _, _, module_doc, _, _} = Code.fetch_docs(module)
    module_doc not in [:hidden, :none]
  end
end
