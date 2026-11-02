defmodule JidoTest.AgentServer.DurableTurn.ApiTest do
  use Covenant.Case, component: "jido.agent_server.durable_turn", async: true

  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.DurableTurn
  alias Jido.AgentServer.DurableTurn.{CheckpointStore, WaitHost}
  alias Jido.Signal

  @tag obligation: "jido.agent_server.durable_turn.I11"
  test "wait delivery stays on the typed AgentServer facade" do
    assert {:function, :deliver_wait, 4} in documented_api(Server)
    assert {:type, :wait_id, 0} in documented_types(Server)

    for module <- [DurableTurn, CheckpointStore, WaitHost] do
      refute public_module?(module)
    end
  end

  @tag obligation: "jido.agent_server.durable_turn.I11"
  test "wait IDs are non-empty strings and fail before server access" do
    signal = Signal.new!("wait.input", %{}, source: "/test")

    for wait_id <- [nil, :wait, 1, ""] do
      assert {:error, %{__exception__: true}} =
               Server.deliver_wait(:not_a_server, wait_id, signal, 0)
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
