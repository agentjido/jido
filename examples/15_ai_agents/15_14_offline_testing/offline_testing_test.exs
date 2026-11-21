Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("offline_testing.ex", __DIR__)

defmodule Jido.Examples.AI.OfflineTestingTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.AI.OfflineTesting.{Agent, ScriptedClient}

  test "pure and hosted execution use the same scripted client contract" do
    id = "offline-testing-#{System.unique_integer([:positive])}"
    source = Agent.instantiate!(id: id)
    request = request("Offline answer.")
    context = %{jido_ai_inference_client: ScriptedClient}

    assert {:ok, pure_candidate, [%Jido.Agent.Directive.Reply{signal: pure_reply}]} =
             Agent.cmd(source, request, context: context)

    assert pure_reply.data.output == "Offline answer."
    assert pure_candidate.state.session.thread.rev > 0

    instance = :"offline_testing_example_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: instance}, id: instance)
    {:ok, server} = Jido.start_agent(instance, source)
    assert :ok = AgentServer.await_ready(server)

    assert {:ok, %AgentServer.TurnResult{status: :committed, reply: hosted_reply}} =
             AgentServer.call(server, request, context: context)

    assert hosted_reply.data.output == pure_reply.data.output

    hosted_state = AgentServer.snapshot(server).agent.state
    assert pure_candidate.state.session.thread.rev == 4
    assert hosted_state.session.thread.rev == 4

    assert Jido.AI.Thread.Projection.messages(hosted_state.session) ==
             Jido.AI.Thread.Projection.messages(pure_candidate.state.session)

    assert :ok = Jido.stop_agent(instance, server)
  end

  test "a scripted provider error records a blocked outcome without an answer" do
    source = Agent.instantiate!(id: "offline-error-#{System.unique_integer([:positive])}")
    request = Agent.request_signal!(%{input: "Fail", options: %{offline_error: :rate_limited}})

    assert {:ok, candidate, [%Jido.Agent.Directive.Reply{signal: reply}]} =
             Agent.cmd(source, request, context: %{jido_ai_inference_client: ScriptedClient})

    assert source.state.session == nil
    assert reply.data.status == :blocked
    assert reply.data.output == ""
    assert {:ok, []} = Jido.AI.Thread.Projection.messages(candidate.state.session)

    assert Enum.any?(candidate.state.session.thread.entries, fn entry ->
             entry.kind == :ai_request_outcome and entry.payload["status"] == "blocked"
           end)
  end

  defp request(response) do
    Agent.request_signal!(%{
      input: "Return the fixture",
      options: %{offline_response: response}
    })
  end
end
