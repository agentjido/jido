defmodule Jido.Examples.ApprovalWorkflow do
  @moduledoc """
  A multi-turn application Agent that searches, selects, approves, and books a flight.

  Reads occur inside the search Flow. Approval commits `:submitting` state and
  returns a booking Directive in a plain effect list. The approval Flow
  preserves that request. The booking Plugin calls the supplied adapter
  after commit and sends one result Signal back to the Agent.
  """

  use Jido.Agent,
    name: "examples_flight_booking",
    description: "Runs a structured flight search and approval process",
    plugins: [Jido.Examples.ApprovalWorkflow.BookingPlugin]

  state do
    schema Jido.Joi.object(%{
             trip_constraints: Jido.Joi.map() |> Jido.Joi.default(%{}),
             search_revision: Jido.Joi.integer() |> Jido.Joi.min(0) |> Jido.Joi.default(0),
             offered_options: Jido.Joi.list(Jido.Joi.map()) |> Jido.Joi.default([]),
             selection: Jido.Joi.map() |> Jido.Joi.default(%{}),
             passenger_ref: Jido.Joi.string() |> Jido.Joi.default(""),
             approval: Jido.Joi.enum([:not_requested, :pending, :approved]) |> Jido.Joi.default(:not_requested),
             booking_status:
               Jido.Joi.enum([
                 :idle,
                 :awaiting_selection,
                 :awaiting_approval,
                 :submitting,
                 :booked,
                 :failed,
                 :cancelled
               ])
               |> Jido.Joi.default(:idle),
             booking_key: Jido.Joi.string() |> Jido.Joi.default(""),
             booking_id: Jido.Joi.string() |> Jido.Joi.default(""),
             last_error: Jido.Joi.string() |> Jido.Joi.default("")
           })
  end

  routes do
    signal_source "/examples/flight_booking"

    route "examples.flight.request", Jido.Examples.ApprovalWorkflow.SearchFlow, as: :search_flights do
    end

    route "examples.flight.preferences_updated", Jido.Examples.ApprovalWorkflow.SearchFlow, as: :update_preferences do
    end

    route "examples.flight.select", Jido.Examples.ApprovalWorkflow.SelectFare, as: :select_fare

    route "examples.flight.approve", Jido.Examples.ApprovalWorkflow.ApproveFlow, as: :approve_booking do
    end

    route "examples.flight.cancel", Jido.Examples.ApprovalWorkflow.Cancel, as: :cancel

    route "examples.flight.booking_succeeded", Jido.Examples.ApprovalWorkflow.BookingSucceeded

    route "examples.flight.booking_failed", Jido.Examples.ApprovalWorkflow.BookingFailed
  end
end
