defmodule JidoTest.Examples.MultiAgent.CorrelatedRequestsTest do
  use JidoTest.FeatureSDKCase

  @moduletag group: :multi_agent

  alias Jido.Examples.CorrelatedRequests

  test "child work and its correlated result use separate parent commits", %{jido: jido} do
    parent = start_agent!(jido, CorrelatedRequests)
    assert {:ok, pending} = CorrelatedRequests.request(parent, "request-1", 7)
    assert pending.state.status == :waiting
    assert Server.snapshot(parent).state_version == 1

    eventually(fn -> state(parent).status == :completed end)
    assert state(parent).result == 14
    assert Server.snapshot(parent).state_version == 2
    eventually(fn -> Server.children(parent) == %{} end)
  end

  test "wrong correlation and duplicate request IDs preserve the candidate" do
    agent = CorrelatedRequests.new!()

    assert {:ok, pending, [_spawn, _send]} =
             CorrelatedRequests.cmd(
               agent,
               CorrelatedRequests.request_signal!("request-1", 7)
             )

    for overrides <- [%{request_id: "old"}, %{tag: "wrong"}, %{job_id: "wrong"}] do
      data =
        Map.merge(
          %{request_id: "request-1", job_id: "request-1", tag: "request-1", value: 14},
          overrides
        )

      signal =
        Jido.Signal.new!("examples.multi_agent.worker.result", data,
          source: "/test/correlated_requests"
        )

      assert {:error, _} = CorrelatedRequests.cmd(pending, signal)
    end

    assert {:error, _} =
             CorrelatedRequests.cmd(
               pending,
               CorrelatedRequests.request_signal!("request-1", 8)
             )
  end

  test "cancellation returns explicit child-stop intent" do
    agent = CorrelatedRequests.new!()

    assert {:ok, pending, _directives} =
             CorrelatedRequests.cmd(
               agent,
               CorrelatedRequests.request_signal!("request-1", 7)
             )

    assert {:ok, cancelled, [%Jido.Agent.Directive.StopChild{tag: "request-1"}]} =
             CorrelatedRequests.cmd(
               pending,
               CorrelatedRequests.cancel_signal!("request-1")
             )

    assert cancelled.state.status == :cancelled
    assert cancelled.state.result == nil
  end
end
