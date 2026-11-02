defmodule JidoTest.AgentServer.PluginRuntime.ApiTest do
  use Covenant.Case, component: "jido.agent_server.plugin_runtime", async: true

  alias Jido.AgentServer.Plugin, as: Runtime
  alias Jido.AgentServer.Plugin.{Admission, Callbacks, Commit, Spec}
  alias Jido.Plugin

  @tag obligation: "jido.agent_server.plugin_runtime.I13"
  test "the live Plugin API exposes only the state facade and callback records" do
    assert {:function, :state, 2} in documented_api(Plugin)

    for module <- [Admission, Commit] do
      assert public_module?(module)
      assert documented_api(module) == []
      assert documented_types(module) == [{:type, :t, 0}]
    end

    for module <- [Runtime, Callbacks, Spec] do
      refute public_module?(module)
    end
  end

  @tag obligation: [
         "jido.agent_server.plugin_runtime.I4",
         "jido.agent_server.plugin_runtime.I6",
         "jido.agent_server.plugin_runtime.I13"
       ]
  test "public callback records keep their exact read-only fields" do
    assert fields(Admission) == [
             :agent_id,
             :agent_module,
             :caller_context,
             :plugin,
             :plugin_state,
             :prepared_input,
             :signal,
             :state_version
           ]

    assert fields(Commit) == [
             :agent_id,
             :agent_module,
             :jido,
             :partition,
             :plugin,
             :plugin_state,
             :state_version,
             :turn_id
           ]
  end

  defp fields(module) do
    module
    |> struct()
    |> Map.from_struct()
    |> Map.keys()
    |> Enum.sort()
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
