defmodule Jido.Examples.ApprovalWorkflow do
  @moduledoc """
  A multi-turn Agent that searches, selects, approves, and books a flight.

  Reads occur inside the search Flow. An approval Action commits `:submitting`
  state and returns a booking Directive. A Plugin without a process submits the
  booking in the Server-owned dispatch task after commit and sends one result
  Signal back to the Agent. Caller context supplies the booking adapter.
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

defmodule Jido.Examples.ApprovalWorkflow.Search do
  @moduledoc "The flight search contract."

  @callback search(client :: term(), constraints :: map()) ::
              {:ok, [map()]} | {:error, term()}
end

defmodule Jido.Examples.ApprovalWorkflow.FixtureSearch do
  @moduledoc "A deterministic flight search that returns one fixture result."

  @behaviour Jido.Examples.ApprovalWorkflow.Search

  @impl Jido.Examples.ApprovalWorkflow.Search
  def search(result, _constraints), do: result
end

defmodule Jido.Examples.ApprovalWorkflow.BookingAPI do
  @moduledoc "The idempotent booking submission contract."

  @callback book(client :: term(), request :: map(), idempotency_key :: String.t()) ::
              {:ok, String.t()} | {:error, term()}
end

defmodule Jido.Examples.ApprovalWorkflow.FakeBookingAPI do
  @moduledoc "A process-backed booking API that deduplicates idempotency keys."

  use Elixir.Agent

  @behaviour Jido.Examples.ApprovalWorkflow.BookingAPI

  @spec start_link(keyword()) :: Elixir.Agent.on_start()
  def start_link(opts \\ []) do
    Elixir.Agent.start_link(fn ->
      %{result: Keyword.get(opts, :result, :ok), bookings: %{}, calls: []}
    end)
  end

  @impl Jido.Examples.ApprovalWorkflow.BookingAPI
  def book(api, request, key) do
    Elixir.Agent.get_and_update(api, fn state ->
      state = %{state | calls: [{key, request} | state.calls]}

      case Map.fetch(state.bookings, key) do
        {:ok, booking_id} ->
          {{:ok, booking_id}, state}

        :error when state.result == :ok ->
          booking_id = "booking-#{map_size(state.bookings) + 1}"

          {{:ok, booking_id},
           %{
             state
             | bookings: Map.put(state.bookings, key, booking_id)
           }}

        :error ->
          {{:error, state.result}, state}
      end
    end)
  end

  @doc "Returns every attempted provider call, including duplicate keys."
  @spec calls(Elixir.Agent.agent()) :: [{String.t(), map()}]
  def calls(api), do: Elixir.Agent.get(api, &Enum.reverse(&1.calls))
end

defmodule Jido.Examples.ApprovalWorkflow.SubmitBooking do
  @moduledoc "A portable post-commit booking request owned by the booking Plugin."

  @schema Zoi.struct(
            __MODULE__,
            %{
              request: Zoi.map(),
              idempotency_key: Zoi.string() |> Zoi.min(1)
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end

defmodule Jido.Examples.ApprovalWorkflow.BookingPlugin do
  @moduledoc "Dispatches typed booking requests without a Plugin process."

  use Jido.Plugin

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.ApprovalWorkflow.SubmitBooking
  alias Jido.Signal

  @doc "Creates one portable booking submission Directive."
  @spec submit(map(), String.t()) :: SubmitBooking.t()
  def submit(request, idempotency_key) do
    %SubmitBooking{request: request, idempotency_key: idempotency_key}
  end

  @impl Jido.Plugin
  def directives(_opts), do: [SubmitBooking]

  @impl Jido.Plugin
  def validate_directive(%SubmitBooking{} = directive, _opts) do
    Zoi.parse(SubmitBooking.schema(), Map.from_struct(directive))
  end

  @impl Jido.Plugin
  def dispatch(nil, %SubmitBooking{} = directive, context, _opts) do
    {module, client} = context.turn_context.booking_adapter

    server = Jido.whereis_agent(context.jido, context.agent_id, partition: context.partition)

    Jido.Examples.Workflow.Observation.record(context.turn_context, :booking, %{
      snapshot: Server.snapshot(server),
      directive: directive
    })

    signal =
      case module.book(client, directive.request, directive.idempotency_key) do
        {:ok, booking_id} ->
          Signal.new!(
            "examples.flight.booking_succeeded",
            %{booking_key: directive.idempotency_key, booking_id: booking_id},
            source: "/examples/flight_booking/plugin"
          )

        {:error, reason} ->
          Signal.new!(
            "examples.flight.booking_failed",
            %{booking_key: directive.idempotency_key, reason: inspect(reason)},
            source: "/examples/flight_booking/plugin"
          )
      end

    Server.cast(server, signal)
  end
end

defmodule Jido.Examples.ApprovalWorkflow.ValidateRequest do
  @moduledoc false

  use Jido.Action, name: "examples_flight_booking_validate_request"

  alias Jido.Action.Error

  @impl Jido.Action
  def run(%{constraints: constraints} = input, _context) do
    case constraints do
      %{origin: origin, destination: destination, date: date, max_price: max_price}
      when is_binary(origin) and is_binary(destination) and origin != destination and
             is_binary(date) and is_number(max_price) and max_price > 0 ->
        case Date.from_iso8601(date) do
          {:ok, _date} -> {:ok, input}
          _result -> {:error, Error.validation_error("flight date is invalid")}
        end

      _constraints ->
        {:error, Error.validation_error("flight constraints are invalid")}
    end
  end
end

defmodule Jido.Examples.ApprovalWorkflow.SearchFlights do
  @moduledoc false

  use Jido.Action, name: "examples_flight_booking_search"

  alias Jido.Action.Error

  @impl Jido.Action
  def run(input, context) do
    {module, client} = context.search

    case module.search(client, input.constraints) do
      {:ok, options} when is_list(options) ->
        {:ok, Map.put(input, :options, options)}

      {:error, reason} ->
        {:error, Error.execution_error("flight search failed", reason: reason)}

      result ->
        {:error, Error.execution_error("flight search returned invalid data", result: result)}
    end
  end
end

defmodule Jido.Examples.ApprovalWorkflow.PrepareOptions do
  @moduledoc false

  use Jido.Action, name: "examples_flight_booking_prepare_options"

  alias Jido.Action.Error

  @impl Jido.Action
  def run(input, %{agent_state: state}) do
    options =
      input.options
      |> Enum.filter(&valid_option?(&1, input.constraints))
      |> Enum.sort_by(&{&1.price, &1.id})

    if options == [] do
      {:error, Error.validation_error("no flight matches the request")}
    else
      {:ok,
       %{
         state
         | trip_constraints: input.constraints,
           search_revision: state.search_revision + 1,
           offered_options: options,
           selection: %{},
           passenger_ref: "",
           approval: :not_requested,
           booking_status: :awaiting_selection,
           booking_key: "",
           booking_id: "",
           last_error: ""
       }}
    end
  end

  defp valid_option?(option, constraints) do
    is_binary(option.id) and option.origin == constraints.origin and
      option.destination == constraints.destination and option.date == constraints.date and
      is_number(option.price) and option.price <= constraints.max_price
  end
end

defmodule Jido.Examples.ApprovalWorkflow.SearchFlow do
  @moduledoc "Validates, searches, filters, and commits one offer revision."

  use Jido.Flow, name: "examples_flight_booking_search_flow"

  flow do
    step "validate",
      action: Jido.Examples.ApprovalWorkflow.ValidateRequest,
      params: %{constraints: input(:constraints)}

    step "search",
      action: Jido.Examples.ApprovalWorkflow.SearchFlights,
      params: result("validate")

    step "prepare",
      action: Jido.Examples.ApprovalWorkflow.PrepareOptions,
      params: result("search")

    output result("prepare")
  end
end

defmodule Jido.Examples.ApprovalWorkflow.SelectFare do
  @moduledoc false

  use Jido.Action,
    name: "examples_flight_booking_select",
    schema:
      Zoi.object(%{
        option_id: Zoi.string() |> Zoi.min(1),
        search_revision: Zoi.integer() |> Zoi.min(1),
        passenger_ref: Zoi.string() |> Zoi.min(1)
      })

  alias Jido.Action.Error

  @impl Jido.Action
  def run(input, %{agent_state: state}) do
    with :ok <- selectable(state),
         :ok <- current_revision(input.search_revision, state.search_revision),
         {:ok, option} <- find_option(state.offered_options, input.option_id) do
      {:ok,
       %{
         state
         | selection: option,
           passenger_ref: input.passenger_ref,
           approval: :pending,
           booking_status: :awaiting_approval
       }}
    end
  end

  defp selectable(%{booking_status: :awaiting_selection}), do: :ok

  defp selectable(_state),
    do: {:error, Error.validation_error("flight is not awaiting selection")}

  defp current_revision(revision, revision), do: :ok

  defp current_revision(_given, _current),
    do: {:error, Error.validation_error("flight search revision is stale")}

  defp find_option(options, id) do
    case Enum.find(options, &(&1.id == id)) do
      nil -> {:error, Error.validation_error("selected fare is not in the current offer set")}
      option -> {:ok, option}
    end
  end
end

defmodule Jido.Examples.ApprovalWorkflow.ApproveBooking do
  @moduledoc false

  use Jido.Action, name: "examples_flight_booking_approve"

  alias Jido.Action.Error
  alias Jido.Examples.ApprovalWorkflow.BookingPlugin

  @impl Jido.Action
  def run(_input, %{agent_id: agent_id, agent_state: state} = context) do
    with {:ok, _adapter} <- booking_adapter(context) do
      if state.booking_status == :awaiting_approval and state.passenger_ref != "" do
        booking_key = "#{agent_id}:#{state.search_revision}:#{state.selection.id}"

        request = %{
          option_id: state.selection.id,
          fare_revision: state.selection.fare_revision,
          passenger_ref: state.passenger_ref
        }

        next_state = %{
          state
          | approval: :approved,
            booking_status: :submitting,
            booking_key: booking_key,
            last_error: ""
        }

        {:ok, next_state, [BookingPlugin.submit(request, booking_key)]}
      else
        {:error, Error.validation_error("flight is not ready for approval")}
      end
    end
  end

  defp booking_adapter(context) do
    case Zoi.parse(Zoi.tuple({Zoi.atom(), Zoi.any()}), Map.get(context, :booking_adapter)) do
      {:ok, adapter} ->
        {:ok, adapter}

      {:error, _issues} ->
        {:error, Error.validation_error("booking adapter is required in caller context")}
    end
  end
end

defmodule Jido.Examples.ApprovalWorkflow.BookingSucceeded do
  @moduledoc false

  use Jido.Action,
    name: "examples_flight_booking_succeeded",
    schema:
      Zoi.object(%{
        booking_key: Zoi.string() |> Zoi.min(1),
        booking_id: Zoi.string() |> Zoi.min(1)
      })

  @impl Jido.Action
  def run(%{booking_key: key, booking_id: booking_id}, %{
        agent_state: %{booking_key: key, booking_status: :submitting} = state
      }) do
    {:ok, %{state | booking_status: :booked, booking_id: booking_id, last_error: ""}}
  end

  def run(_input, %{agent_state: state}), do: {:ok, state}
end

defmodule Jido.Examples.ApprovalWorkflow.BookingFailed do
  @moduledoc false

  use Jido.Action,
    name: "examples_flight_booking_failed",
    schema: Zoi.object(%{booking_key: Zoi.string() |> Zoi.min(1), reason: Zoi.string()})

  @impl Jido.Action
  def run(%{booking_key: key, reason: reason}, %{
        agent_state: %{booking_key: key, booking_status: :submitting} = state
      }) do
    {:ok, %{state | booking_status: :failed, last_error: reason}}
  end

  def run(_input, %{agent_state: state}), do: {:ok, state}
end

defmodule Jido.Examples.ApprovalWorkflow.Cancel do
  @moduledoc false

  use Jido.Action, name: "examples_flight_booking_cancel"

  alias Jido.Action.Error

  @impl Jido.Action
  def run(_input, %{agent_state: %{booking_status: status} = state})
      when status in [:awaiting_selection, :awaiting_approval] do
    {:ok, %{state | booking_status: :cancelled, approval: :not_requested}}
  end

  def run(_input, _context) do
    {:error, Error.validation_error("flight can no longer be cancelled")}
  end
end
