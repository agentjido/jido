defmodule Jido.Examples.ApprovalWorkflow.FixtureSearch do
  @moduledoc "A deterministic flight search that returns one configured result."

  @behaviour Jido.Examples.ApprovalWorkflow.Search

  @impl true
  def search(result, _constraints), do: result
end

defmodule Jido.Examples.ApprovalWorkflow.FakeBookingAPI do
  @moduledoc "A local booking adapter that deduplicates idempotency keys."

  use Elixir.Agent

  @behaviour Jido.Examples.ApprovalWorkflow.BookingAPI

  @spec start_link(keyword()) :: Elixir.Agent.on_start()
  def start_link(opts \\ []) do
    Elixir.Agent.start_link(fn ->
      %{result: Keyword.get(opts, :result, :ok), bookings: %{}, calls: []}
    end)
  end

  @impl true
  def book(api, request, key) do
    Elixir.Agent.get_and_update(api, fn state ->
      state = %{state | calls: [{key, request} | state.calls]}

      case Map.fetch(state.bookings, key) do
        {:ok, booking_id} ->
          {{:ok, booking_id}, state}

        :error when state.result == :ok ->
          booking_id = "booking-#{map_size(state.bookings) + 1}"
          {{:ok, booking_id}, %{state | bookings: Map.put(state.bookings, key, booking_id)}}

        :error ->
          {{:error, state.result}, state}
      end
    end)
  end

  @doc "Returns every attempted provider call, including duplicate keys."
  @spec calls(Elixir.Agent.agent()) :: [{String.t(), map()}]
  def calls(api), do: Elixir.Agent.get(api, &Enum.reverse(&1.calls))
end
