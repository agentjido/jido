Code.require_file("request_modes.ex", __DIR__)

defmodule Jido.Examples.AI.RequestModesTest do
  use Jido.Test.Case, async: false
  import Mimic

  @moduletag :integration

  setup :set_mimic_global
  setup :verify_on_exit!

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.AI.RequestModes
  alias Jido.Test.Examples.AIModel

  test "call and submit return replies while cast discards its reply", %{jido: jido} do
    AIModel.expect_text("Offline answer.", 3)
    assert {:ok, server} = RequestModes.start(jido, id: unique_id("request-modes"))
    assert :ok = Jido.AgentServer.await_ready(server)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed, reply: %Jido.Signal{}}} =
             Server.call(server, RequestModes.Agent.request_signal!(%{input: "call"}))

    called = Server.snapshot(server).agent

    pending = Server.submit(server, RequestModes.Agent.request_signal!(%{input: "submit"}))

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed, reply: %Jido.Signal{}}} =
             Server.await(pending)

    submitted = Server.snapshot(server).agent

    assert :ok = Server.cast(server, RequestModes.Agent.request_signal!(%{input: "cast"}))
    assert {:ok, _status} = Server.quiesce(server)
    casted = Server.snapshot(server).agent

    assert called.state.session.thread.rev < submitted.state.session.thread.rev
    assert submitted.state.session.thread.rev < casted.state.session.thread.rev

    assistants =
      Enum.filter(casted.state.session.thread.entries, fn entry ->
        entry.kind == :ai_message and entry.payload["role"] == "assistant"
      end)

    assert length(assistants) == 3
    assert :ok = Jido.stop_agent(jido, server)
  end
end
