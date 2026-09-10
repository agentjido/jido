defmodule Jido.Examples.ApprovalWorkflow.ValidateRequest do
  @moduledoc false

  use Jido.Action,
    name: "examples_flight_booking_validate_request",
    schema: Zoi.object(%{constraints: Zoi.map()})

  alias Jido.Action.Error

  @impl true
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

  use Jido.Action,
    name: "examples_flight_booking_search",
    schema: Zoi.object(%{constraints: Zoi.map()})

  alias Jido.Action.Error

  @impl true
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

  use Jido.Action,
    name: "examples_flight_booking_prepare_options",
    schema:
      Zoi.object(%{
        constraints: Zoi.map(),
        options: Zoi.list(Zoi.map())
      })

  alias Jido.Action.Error

  @impl true
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

  use Jido.Flow,
    name: "examples_flight_booking_search_flow",
    schema: Zoi.object(%{constraints: Zoi.map()})

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
