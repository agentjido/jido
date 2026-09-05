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

  defp search(server),
    do:
      Example.search_flights(server,
        input: %{constraints: @constraints},
        context: %{search: {FixtureSearch, {:ok, @offers}}}
      )

  defp select(server, revision \\ 1),
    do: Example.select_fare(server, "fare-1", revision, "passenger-ref")

  defp approve_signal, do: signal("examples.flight.approve")

  test "approval commits before a process-free Plugin books and a later Signal completes", %{
    jido: jido
  } do
    api = start_supervised!(FakeBookingAPI)
    server = start_agent!(jido, Example)
    refute Map.has_key?(Server.children(server), {:plugin, BookingPlugin})
    assert {:ok, _} = search(server)
    assert {:ok, selected} = select(server)
    ctx = context([:booking], %{booking_adapter: {FakeBookingAPI, api}})

    assert {:ok, candidate, [%SubmitBooking{} = directive]} =
             Example.cmd(selected, approve_signal(), context: ctx)

    assert Map.keys(Map.from_struct(directive)) |> Enum.sort() == [:idempotency_key, :request]
    assert FakeBookingAPI.calls(api) == []
    assert Server.agent(server) == selected
    caller = call_async(server, approve_signal(), ctx)

    assert_receive {:step, :booking, worker,
                    %{snapshot: %{agent: ^candidate, state_version: 3}, directive: ^directive}},
                   1_000

    assert candidate.state.booking_status == :submitting
    assert FakeBookingAPI.calls(api) == []
    send(worker, {:release, :booking})
    assert {:ok, ^candidate} = Task.await(caller)
    eventually(fn -> Server.agent(server).state.booking_status == :booked end)
    assert Server.snapshot(server).state_version == 4
    assert [{key, request}] = FakeBookingAPI.calls(api)
    assert key == candidate.state.booking_key
    assert request.passenger_ref == "passenger-ref"
  end

  test "a valid stale revision fails selection and cancelled work cannot be approved", %{
    jido: jido
  } do
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

    assert {:error, _} =
             Example.approve_booking(server, context: %{booking_adapter: {FakeBookingAPI, api}})

    assert Server.snapshot(server) == before
    assert FakeBookingAPI.calls(api) == []
  end

  test "queued duplicate approval creates only one provider attempt", %{jido: jido} do
    api = start_supervised!(FakeBookingAPI)
    server = start_agent!(jido, Example)
    assert {:ok, _} = search(server)
    assert {:ok, _} = select(server)

    first =
      call_async(
        server,
        approve_signal(),
        context([:booking], %{booking_adapter: {FakeBookingAPI, api}})
      )

    assert_receive {:step, :booking, worker, _}, 1_000
    duplicate = call_async(server, approve_signal(), %{booking_adapter: {FakeBookingAPI, api}})
    eventually(fn -> Server.status(server).admission.postponed == 1 end)
    send(worker, {:release, :booking})
    assert {:ok, _} = Task.await(first)
    assert {:error, error} = Task.await(duplicate)
    assert Enum.any?(errors(error), &(&1.message == "flight is not ready for approval"))
    eventually(fn -> Server.agent(server).state.booking_status == :booked end)
    assert length(FakeBookingAPI.calls(api)) == 1
    assert Server.snapshot(server).state_version == 4
  end

  test "stale and duplicate result Signals cannot replace a terminal booking", %{jido: jido} do
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
      signal("examples.flight.booking_succeeded", %{
        booking_key: approved.state.booking_key,
        booking_id: "duplicate"
      }),
      signal("examples.flight.booking_failed", %{
        booking_key: approved.state.booking_key,
        reason: "late failure"
      })
    ]

    for message <- messages, do: assert({:ok, ^booked} = Server.call(server, message))
    # An accepted no-op is still a successful commit revision.
    assert Server.snapshot(server) == %{agent: booked, state_version: 7}
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
    assert Server.snapshot(server).state_version == 4
    assert length(FakeBookingAPI.calls(api)) == 1
  end
end
