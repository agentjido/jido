defmodule Jido.Examples.Durable.ExternalUncertainty.MemoryProvider do
  @moduledoc "A local provider that rejects reuse of an operation ID with different data."
  use GenServer

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, nil, name: Keyword.fetch!(opts, :name))

  def publish(address, id, report), do: GenServer.call(address, {:publish, id, report})
  def records(address), do: GenServer.call(address, :records)
  def attempts(address), do: GenServer.call(address, :attempts)

  @impl true
  def init(_), do: {:ok, %{records: %{}, attempts: 0}}

  @impl true
  def handle_call({:publish, id, report}, _from, state) do
    state = %{state | attempts: state.attempts + 1}

    case Map.fetch(state.records, id) do
      :error ->
        {:reply, :ok, %{state | records: Map.put(state.records, id, report)}}

      {:ok, ^report} ->
        {:reply, :ok, state}

      {:ok, _} ->
        {:reply, {:error, Jido.Action.Error.validation_error("operation ID has different data")},
         state}
    end
  end

  def handle_call(:records, _, state), do: {:reply, state.records, state}
  def handle_call(:attempts, _, state), do: {:reply, state.attempts, state}
end
