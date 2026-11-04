defmodule JidoTest.AgentServer.DurableTurn.ApiTest do
  use Covenant.Case, component: "jido.agent_server.durable_turn", async: true

  import Jido.Test.PublicAPI

  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.Lifecycle
  alias Jido.Exec.{Continuation, Wait}
  alias Jido.Persistence.ContinuationStore
  alias Jido.Persistence.ContinuationStore.JoinCompletedRef
  alias Jido.Signal

  @tag obligation: "jido.agent_server.durable_turn.I11"
  test "wait delivery stays on the typed AgentServer facade" do
    assert {:function, :deliver_wait, 4} in documented_api(Server)
    assert {:type, :id, 0} in documented_types(Wait)
    assert {:type, :t, 0} in documented_types(Continuation)
    refute {:type, :wait_id, 0} in documented_types(Server)
    assert public_module?(Continuation)

    for module <- [Lifecycle, ContinuationStore, JoinCompletedRef] do
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
end
