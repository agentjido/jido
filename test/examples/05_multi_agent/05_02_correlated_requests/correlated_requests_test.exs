defmodule JidoTest.Examples.MultiAgent.CorrelatedRequestsTest do
  use JidoTest.FeatureSDKCase

  @moduletag group: :multi_agent

  alias Jido.Examples.CorrelatedRequests

  test "child work and its correlated result use separate parent commits", %{jido: jido} do
    parent = start_agent!(jido, CorrelatedRequests)

    {:ok, route_signal_1} =
      CorrelatedRequests.request_signal(%{request_id: "request-1", value: 7})

    assert {:ok, pending} =
             Jido.AgentServer.call(parent, route_signal_1, [])

    assert pending.state.status == :waiting
    pending_version = Server.snapshot(parent).state_version
    assert pending_version == 1

    eventually(fn -> state(parent).status == :completed end)
    assert state(parent).result == 14
    assert Server.snapshot(parent).state_version > pending_version
    eventually(fn -> Server.children(parent) == %{} end)
  end

  test "wrong correlation and duplicate request IDs preserve the candidate" do
    agent = CorrelatedRequests.new!()

    {:ok, command_signal_1} =
      CorrelatedRequests.request_signal(%{request_id: "request-1", value: 7})

    assert {:ok, pending, [_spawn, _send]} =
             CorrelatedRequests.cmd(
               agent,
               command_signal_1
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

    {:ok, command_signal_2} =
      CorrelatedRequests.request_signal(%{request_id: "request-1", value: 8})

    assert {:error, _} =
             CorrelatedRequests.cmd(
               pending,
               command_signal_2
             )
  end

  test "cancellation returns explicit child-stop intent" do
    agent = CorrelatedRequests.new!()

    {:ok, command_signal_3} =
      CorrelatedRequests.request_signal(%{request_id: "request-1", value: 7})

    assert {:ok, pending, _directives} =
             CorrelatedRequests.cmd(
               agent,
               command_signal_3
             )

    {:ok, command_signal_4} = CorrelatedRequests.cancel_signal(%{request_id: "request-1"})

    assert {:ok, cancelled, [%Jido.Agent.Directive.StopChild{tag: "request-1"}]} =
             CorrelatedRequests.cmd(
               pending,
               command_signal_4
             )

    assert cancelled.state.status == :cancelled
    assert cancelled.state.result == nil
  end
end
