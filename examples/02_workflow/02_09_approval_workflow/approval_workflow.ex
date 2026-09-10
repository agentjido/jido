defmodule Jido.Examples.ApprovalWorkflow do
  @moduledoc """
  A multi-turn Agent that searches, selects, approves, and books a flight.

  Reads occur inside the search Flow. Approval commits `:submitting` state and
  returns a booking Directive. The booking Plugin calls the supplied adapter
  after commit and sends one result Signal back to the Agent.
  """

  use Jido.Agent,
    name: "examples_flight_booking",
    description: "Runs a structured flight search and approval process"

  agent do
    schema Zoi.object(%{
             trip_constraints: Zoi.map() |> Zoi.default(%{}),
             search_revision: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0),
             offered_options: Zoi.list(Zoi.map()) |> Zoi.default([]),
             selection: Zoi.map() |> Zoi.default(%{}),
             passenger_ref: Zoi.string() |> Zoi.default(""),
             approval:
               Zoi.enum([:not_requested, :pending, :approved]) |> Zoi.default(:not_requested),
             booking_status:
               Zoi.enum([
                 :idle,
                 :awaiting_selection,
                 :awaiting_approval,
                 :submitting,
                 :booked,
                 :failed,
                 :cancelled
               ])
               |> Zoi.default(:idle),
             booking_key: Zoi.string() |> Zoi.default(""),
             booking_id: Zoi.string() |> Zoi.default(""),
             last_error: Zoi.string() |> Zoi.default("")
           })

    plugin Jido.Examples.ApprovalWorkflow.BookingPlugin
  end

  routes do
    signal_source "/examples/flight_booking"

    route "examples.flight.request", Jido.Examples.ApprovalWorkflow.SearchFlow do
      define :search_flights
    end

    route "examples.flight.preferences_updated", Jido.Examples.ApprovalWorkflow.SearchFlow do
      define :update_preferences
    end

    route "examples.flight.select", Jido.Examples.ApprovalWorkflow.SelectFare do
      define :select_fare, args: [:option_id, :search_revision, :passenger_ref]
    end

    route "examples.flight.approve", Jido.Examples.ApprovalWorkflow.ApproveBooking do
      define :approve_booking
    end

    route "examples.flight.cancel", Jido.Examples.ApprovalWorkflow.Cancel do
      define :cancel
    end

    route "examples.flight.booking_succeeded", Jido.Examples.ApprovalWorkflow.BookingSucceeded
    route "examples.flight.booking_failed", Jido.Examples.ApprovalWorkflow.BookingFailed
  end
end
