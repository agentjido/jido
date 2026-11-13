Code.require_file("ports.ex", __DIR__)
Code.require_file("support/adapters.ex", __DIR__)
Code.require_file("booking_actions.ex", __DIR__)
Code.require_file("booking_plugin.ex", __DIR__)
Code.require_file("search_flow.ex", __DIR__)
Code.require_file("approval_workflow.ex", __DIR__)

defmodule Jido.Examples.Applications.ApprovalWorkflowTest do
  use Jido.Test.Agent.WorkflowSDKCase
  @moduletag :integration

  alias Jido.Examples.ApprovalWorkflow, as: Example

  alias Jido.Examples.ApprovalWorkflow.{
    ApproveBooking,
    ApproveFlow,
    FakeBookingAPI,
    FixtureSearch,
    SubmitBooking
  }

  @constraints %{origin: "ORD", destination: "LAX", date: "2026-10-01", max_price: 400}
  @offers [
    %{
      id: "fare-1",
      origin: "ORD",
      destination: "LAX",
      date: "2026-10-01",
      price: 300,
      fare_revision: "r1"
    }
  ]

  defp search(server) do
    {:ok, route_signal_1} = Example.search_flights_signal(%{constraints: @constraints})

    Jido.AgentServer.call(server, route_signal_1, context: %{search: {FixtureSearch, {:ok, @offers}}})
  end

  defp select(server, revision \\ 1) do
    {:ok, route_signal_2} =
      Example.select_fare_signal(%{
        option_id: "fare-1",
        search_revision: revision,
        passenger_ref: "passenger-ref"
      })

    Jido.AgentServer.call(server, route_signal_2, [])
  end

  defp approve_signal, do: signal("examples.flight.approve")

  test "approval returns a portable Directive and live dispatch completes in a later Turn", %{
    jido: jido
  } do
    api = start_supervised!(FakeBookingAPI)
    server = start_agent!(jido, Example)
    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} = search(server)
    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} = select(server)
    selected = Jido.AgentServer.snapshot(server).agent
    context = %{booking_adapter: {FakeBookingAPI, api}}

    assert {:ok, candidate, [%SubmitBooking{} = directive]} =
             Example.cmd(selected, approve_signal(), context: context)

    execution_context = Map.merge(context, %{agent_id: selected.id, agent_state: selected.state})
    direct = Jido.Exec.run(ApproveBooking, %{}, execution_context)
    assert direct == Jido.Exec.run(ApproveFlow, %{}, execution_context)
    assert {:ok, _, [^directive]} = direct

    assert Map.keys(Map.from_struct(directive)) |> Enum.sort() == [:idempotency_key, :request]
    assert candidate.state.booking_status == :submitting
    assert FakeBookingAPI.calls(api) == []
    assert Jido.AgentServer.snapshot(server).agent == selected

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, approve_signal(), context: context)

      assert turn_result.status in [:committed, :waiting]
      assert candidate == Jido.AgentServer.snapshot(server).agent
    )

    eventually(fn -> Jido.AgentServer.snapshot(server).agent.state.booking_status == :booked end)

    assert [{key, request}] = FakeBookingAPI.calls(api)
    assert key == candidate.state.booking_key
    assert request.passenger_ref == "passenger-ref"
    assert Jido.AgentServer.snapshot(server).agent_revision == 4
  end

  test "a stale selection fails and cancelled work cannot be approved", %{jido: jido} do
    api = start_supervised!(FakeBookingAPI)
    server = start_agent!(jido, Example)
    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} = search(server)

    {:ok, route_signal_3} = Example.update_preferences_signal(%{constraints: @constraints})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, route_signal_3, context: %{search: {FixtureSearch, {:ok, @offers}}})

      assert turn_result.status in [:committed, :waiting]
      refreshed = Jido.AgentServer.snapshot(server).agent
    )

    assert refreshed.state.search_revision == 2
    before = Jido.AgentServer.snapshot(server)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: error}} =
             select(server, 1)

    assert Enum.any?(errors(error), &(&1.message == "flight search revision is stale"))
    assert Jido.AgentServer.snapshot(server) == before

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} = select(server, 2)

    {:ok, route_signal_4} = Example.cancel_signal(%{})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, route_signal_4, [])

      assert turn_result.status in [:committed, :waiting]
      cancelled = Jido.AgentServer.snapshot(server).agent
    )

    assert cancelled.state.booking_status == :cancelled
    before = Jido.AgentServer.snapshot(server)

    {:ok, route_signal_5} = Example.approve_booking_signal(%{})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: _error}} =
             Jido.AgentServer.call(server, route_signal_5, context: %{booking_adapter: {FakeBookingAPI, api}})

    assert Jido.AgentServer.snapshot(server) == before
    assert FakeBookingAPI.calls(api) == []
  end

  test "a duplicate approval makes no second provider call", %{jido: jido} do
    api = start_supervised!(FakeBookingAPI)
    server = start_agent!(jido, Example)
    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} = search(server)
    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} = select(server)
    context = %{booking_adapter: {FakeBookingAPI, api}}

    {:ok, route_signal_6} = Example.approve_booking_signal(%{})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, route_signal_6, context: context)

      assert turn_result.status in [:committed, :waiting]
      _submitting = Jido.AgentServer.snapshot(server).agent
    )

    eventually(fn -> Jido.AgentServer.snapshot(server).agent.state.booking_status == :booked end)

    {:ok, route_signal_7} = Example.approve_booking_signal(%{})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: error}} =
             Jido.AgentServer.call(server, route_signal_7, context: context)

    assert Enum.any?(errors(error), &(&1.message == "flight is not ready for approval"))
    assert length(FakeBookingAPI.calls(api)) == 1
  end

  test "stale result Signals cannot replace a terminal booking", %{jido: jido} do
    api = start_supervised!(FakeBookingAPI)
    server = start_agent!(jido, Example)
    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} = search(server)
    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} = select(server)

    {:ok, route_signal_8} = Example.approve_booking_signal(%{})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, route_signal_8, context: %{booking_adapter: {FakeBookingAPI, api}})

      assert turn_result.status in [:committed, :waiting]
      approved = Jido.AgentServer.snapshot(server).agent
    )

    eventually(fn -> Jido.AgentServer.snapshot(server).agent.state.booking_status == :booked end)
    booked = Jido.AgentServer.snapshot(server).agent

    messages = [
      signal("examples.flight.booking_succeeded", %{
        booking_key: "old-search",
        booking_id: "wrong"
      }),
      signal("examples.flight.booking_failed", %{
        booking_key: approved.state.booking_key,
        reason: "late failure"
      })
    ]

    for message <- messages do
      assert(
        {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
          Jido.AgentServer.call(server, message)
      )

      assert turn_result.status in [:committed, :waiting]
      assert booked == Jido.AgentServer.snapshot(server).agent
    end

    assert length(FakeBookingAPI.calls(api)) == 1
  end

  test "provider failure enters through a separate result Turn", %{jido: jido} do
    api = start_supervised!({FakeBookingAPI, result: :timeout})
    server = start_agent!(jido, Example)
    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} = search(server)
    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} = select(server)

    {:ok, route_signal_9} = Example.approve_booking_signal(%{})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, route_signal_9, context: %{booking_adapter: {FakeBookingAPI, api}})

      assert turn_result.status in [:committed, :waiting]
      agent = Jido.AgentServer.snapshot(server).agent
    )

    assert agent.state.booking_status == :submitting
    eventually(fn -> Jido.AgentServer.snapshot(server).agent.state.booking_status == :failed end)
    assert Jido.AgentServer.snapshot(server).agent.state.last_error == ":timeout"
    assert length(FakeBookingAPI.calls(api)) == 1
  end
end
