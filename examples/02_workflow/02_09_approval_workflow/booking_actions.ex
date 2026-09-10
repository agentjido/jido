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

  @impl true
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

  use Jido.Action,
    name: "examples_flight_booking_approve",
    schema: Zoi.object(%{})

  alias Jido.Action.Error
  alias Jido.Examples.ApprovalWorkflow.BookingPlugin

  @impl true
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

  @impl true
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

  @impl true
  def run(%{booking_key: key, reason: reason}, %{
        agent_state: %{booking_key: key, booking_status: :submitting} = state
      }) do
    {:ok, %{state | booking_status: :failed, last_error: reason}}
  end

  def run(_input, %{agent_state: state}), do: {:ok, state}
end

defmodule Jido.Examples.ApprovalWorkflow.Cancel do
  @moduledoc false

  use Jido.Action,
    name: "examples_flight_booking_cancel",
    schema: Zoi.object(%{})

  alias Jido.Action.Error

  @impl true
  def run(_input, %{agent_state: %{booking_status: status} = state})
      when status in [:awaiting_selection, :awaiting_approval] do
    {:ok, %{state | booking_status: :cancelled, approval: :not_requested}}
  end

  def run(_input, _context) do
    {:error, Error.validation_error("flight can no longer be cancelled")}
  end
end
