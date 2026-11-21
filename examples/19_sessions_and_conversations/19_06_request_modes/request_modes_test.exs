Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("request_modes.ex", __DIR__)

defmodule Jido.Examples.AI.RequestModesTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.AI.RequestModes
  alias Jido.Examples.Support.OfflineInferenceClient

  test "call and submit return replies while cast has no reply owner" do
    instance = :request_modes_example
    start_supervised!({Jido, name: instance}, id: instance)

    assert {:ok, server} =
             RequestModes.start(instance,
               id: "request-modes-#{System.unique_integer([:positive])}"
             )

    assert :ok = Server.await_ready(server)
    context = %{jido_ai_inference_client: OfflineInferenceClient}

    assert {:ok, %Server.TurnResult{status: :committed, reply: %Jido.Signal{}}} =
             Server.call(server, request("call"), context: context)

    called = Server.snapshot(server).agent
    pending = Server.submit(server, request("submit"), context: context)

    assert {:ok, %Server.TurnResult{status: :committed, reply: %Jido.Signal{}}} =
             Server.await(pending)

    submitted = Server.snapshot(server).agent
    assert :ok = Server.cast(server, request("cast"), context: context)
    assert {:ok, _status} = Server.quiesce(server)
    casted = Server.snapshot(server).agent

    assert called.state.session.thread.rev < submitted.state.session.thread.rev
    assert submitted.state.session.thread.rev < casted.state.session.thread.rev
    assert :ok = Jido.stop_agent(instance, server)
  end

  defp request(input) do
    RequestModes.Agent.request_signal!(%{
      input: input,
      options: %{offline_response: "Offline answer."}
    })
  end
end
