defmodule JidoTest.Examples.Workflow.ApprovalWorkflowTest do
  use JidoTest.WorkflowSDKCase

  alias Jido.Examples.ApprovalWorkflow, as: Example

  alias Jido.Examples.ApprovalWorkflow.{
    BookingPlugin,
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
    Example.search_flights(server,
      input: %{constraints: @constraints},
      context: %{search: {FixtureSearch, {:ok, @offers}}}
    )
  end

  defp select(server, revision \\ 1),
    do: Example.select_fare(server, "fare-1", revision, "passenger-ref")

  defp approve_signal, do: signal("examples.flight.approve")

  test "approval returns a portable Directive and live dispatch completes in a later Turn", %{
    jido: jido
  } do
    api = start_supervised!(FakeBookingAPI)
    server = start_agent!(jido, Example)
    refute Map.has_key?(Server.children(server), {:plugin, BookingPlugin})
    assert {:ok, _} = search(server)
    assert {:ok, selected} = select(server)
    context = %{booking_adapter: {FakeBookingAPI, api}}

    assert {:ok, candidate, [%SubmitBooking{} = directive]} =
             Example.cmd(selected, approve_signal(), context: context)

    assert Map.keys(Map.from_struct(directive)) |> Enum.sort() == [:idempotency_key, :request]
    assert candidate.state.booking_status == :submitting
    assert FakeBookingAPI.calls(api) == []
    assert Server.agent(server) == selected

    assert {:ok, ^candidate} = Server.call(server, approve_signal(), context: context)
    eventually(fn -> Server.agent(server).state.booking_status == :booked end)

    assert [{key, request}] = FakeBookingAPI.calls(api)
    assert key == candidate.state.booking_key
    assert request.passenger_ref == "passenger-ref"
    assert Server.snapshot(server).state_version == 4
  end

  test "a stale selection fails and cancelled work cannot be approved", %{jido: jido} do
    api = start_supervised!(FakeBookingAPI)
    server = start_agent!(jido, Example)
    assert {:ok, _} = search(server)

    assert {:ok, refreshed} =
             Example.update_preferences(server,
               input: %{constraints: @constraints},
               context: %{search: {FixtureSearch, {:ok, @offers}}}
             )

    assert refreshed.state.search_revision == 2
    before = Server.snapshot(server)
    assert {:error, error} = select(server, 1)
    assert Enum.any?(errors(error), &(&1.message == "flight search revision is stale"))
    assert Server.snapshot(server) == before

    assert {:ok, _} = select(server, 2)
    assert {:ok, cancelled} = Example.cancel(server)
    assert cancelled.state.booking_status == :cancelled
    before = Server.snapshot(server)

    assert {:error, _error} =
             Example.approve_booking(server, context: %{booking_adapter: {FakeBookingAPI, api}})

    assert Server.snapshot(server) == before
    assert FakeBookingAPI.calls(api) == []
  end

  test "a duplicate approval makes no second provider call", %{jido: jido} do
    api = start_supervised!(FakeBookingAPI)
    server = start_agent!(jido, Example)
    assert {:ok, _} = search(server)
    assert {:ok, _} = select(server)
    context = %{booking_adapter: {FakeBookingAPI, api}}

    assert {:ok, _submitting} = Example.approve_booking(server, context: context)
    eventually(fn -> Server.agent(server).state.booking_status == :booked end)

    assert {:error, error} = Example.approve_booking(server, context: context)
    assert Enum.any?(errors(error), &(&1.message == "flight is not ready for approval"))
    assert length(FakeBookingAPI.calls(api)) == 1
  end

  test "stale result Signals cannot replace a terminal booking", %{jido: jido} do
    api = start_supervised!(FakeBookingAPI)
    server = start_agent!(jido, Example)
    assert {:ok, _} = search(server)
    assert {:ok, _} = select(server)

    assert {:ok, approved} =
             Example.approve_booking(server, context: %{booking_adapter: {FakeBookingAPI, api}})

    eventually(fn -> Server.agent(server).state.booking_status == :booked end)
    booked = Server.agent(server)

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

    for message <- messages, do: assert({:ok, ^booked} = Server.call(server, message))
    assert length(FakeBookingAPI.calls(api)) == 1
  end

  test "provider failure enters through a separate result Turn", %{jido: jido} do
    api = start_supervised!({FakeBookingAPI, result: :timeout})
    server = start_agent!(jido, Example)
    assert {:ok, _} = search(server)
    assert {:ok, _} = select(server)

    assert {:ok, agent} =
             Example.approve_booking(server, context: %{booking_adapter: {FakeBookingAPI, api}})

    assert agent.state.booking_status == :submitting
    eventually(fn -> Server.agent(server).state.booking_status == :failed end)
    assert Server.agent(server).state.last_error == ":timeout"
    assert length(FakeBookingAPI.calls(api)) == 1
  end
end
