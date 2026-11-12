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

  test "call and submit commit replies while cast cannot commit a reply route", %{jido: jido} do
    AIModel.expect_text("Offline answer.", 2)
    assert {:ok, server} = RequestModes.start(jido, id: unique_id("request-modes"))
    assert :ok = Server.await_ready(server)

    assert {:ok, called, call_directives} =
             Server.call(server, RequestModes.Agent.request_signal!(%{input: "call"}))

    assert [%Jido.Agent.Directive.Reply{}] = call_directives

    pending = Server.submit(server, RequestModes.Agent.request_signal!(%{input: "submit"}))
    assert {:ok, submitted, submit_directives} = Server.await(pending)
    assert [%Jido.Agent.Directive.Reply{}] = submit_directives

    assert :ok = Server.cast(server, RequestModes.Agent.request_signal!(%{input: "cast"}))
    assert :ok = Server.quiesce(server)
    casted = Server.agent(server)

    assert called.state.session.thread.rev < submitted.state.session.thread.rev
    assert submitted.state.session.thread.rev == casted.state.session.thread.rev

    assistants =
      Enum.filter(casted.state.session.thread.entries, fn entry ->
        entry.kind == :ai_message and entry.payload["role"] == "assistant"
      end)

    assert length(assistants) == 2
    assert :ok = Jido.stop_agent(jido, server)
  end
end
