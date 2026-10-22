defmodule JidoTest.AgentServer.ApiTest do
  use Covenant.Case, component: "jido.agent_server", async: true

  alias Jido.AgentServer
  alias Jido.AgentServer.{Core, Pending, Store}

  @tag obligation: "jido.agent_server.I9"
  test "the documented AgentServer facade and public types are exact" do
    assert documented_api(AgentServer) == [
             {:function, :abandon, 1},
             {:function, :activation, 1},
             {:function, :adopt_child, 4},
             {:function, :agent, 2},
             {:function, :alive?, 1},
             {:function, :attach, 3},
             {:function, :await, 2},
             {:function, :await_ready, 2},
             {:function, :call, 3},
             {:function, :cancel, 2},
             {:function, :cancel_turn, 3},
             {:function, :cast, 3},
             {:function, :child_spec, 1},
             {:function, :children, 2},
             {:function, :deliver_wait, 4},
             {:function, :detach, 3},
             {:function, :hibernate, 2},
             {:function, :history, 1},
             {:function, :members, 3},
             {:function, :plugin_state, 3},
             {:function, :quiesce, 2},
             {:function, :resume, 2},
             {:function, :snapshot, 2},
             {:function, :spawn_child, 4},
             {:function, :start, 1},
             {:function, :start_link, 1},
             {:function, :status, 2},
             {:function, :stop, 3},
             {:function, :stop_child, 3},
             {:function, :submit, 3},
             {:function, :touch, 1},
             {:function, :upgrade, 3},
             {:function, :whereis, 3},
             {:function, :worker, 1}
           ]

    assert documented_types(AgentServer) == [
             {:type, :adoption_option, 0},
             {:type, :child_info, 0},
             {:type, :child_option, 0},
             {:type, :child_tag, 0},
             {:type, :pending, 0},
             {:type, :server, 0},
             {:type, :signal_result, 0},
             {:type, :snapshot, 0},
             {:type, :upgrade_option, 0},
             {:type, :wait_id, 0}
           ]

    assert public_module?(AgentServer)

    for module <- [Core, Pending, Store] do
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
