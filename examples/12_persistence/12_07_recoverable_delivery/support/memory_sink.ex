defmodule Jido.Examples.RecoverableDelivery.MemorySink do
  @moduledoc "A deterministic local sink with idempotent effect IDs."

  use GenServer

  @behaviour Jido.Examples.RecoverableDelivery.Sink

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: address(Keyword.fetch!(opts, :jido)))
  end

  def records(jido), do: GenServer.call(address(jido), :records)
  def available(jido, value), do: GenServer.call(address(jido), {:available, value})

  @impl Jido.Examples.RecoverableDelivery.Sink
  def deliver(jido, directive), do: GenServer.call(address(jido), {:deliver, directive})

  @impl true
  def init(_opts), do: {:ok, %{records: %{}, availability: :available}}

  @impl true
  def handle_call(:records, _from, state), do: {:reply, state.records, state}

  def handle_call({:available, value}, _from, state),
    do: {:reply, :ok, %{state | availability: availability(value)}}

  def handle_call({:deliver, _directive}, _from, %{availability: :unavailable} = state),
    do: {:reply, {:error, :sink_unavailable}, state}

  def handle_call(
        {:deliver, %{effect_id: id, value: value}},
        _from,
        %{availability: :uncertain_once} = state
      ) do
    case Map.fetch(state.records, id) do
      :error ->
        next = %{state | records: Map.put(state.records, id, value), availability: :available}
        {:reply, {:error, :outcome_unknown}, next}

      {:ok, ^value} ->
        {:reply, :ok, %{state | availability: :available}}

      {:ok, _other} ->
        {:reply, {:error, :effect_identity_conflict}, state}
    end
  end

  def handle_call({:deliver, %{effect_id: id, value: value}}, _from, state) do
    case Map.fetch(state.records, id) do
      :error -> {:reply, :ok, %{state | records: Map.put(state.records, id, value)}}
      {:ok, ^value} -> {:reply, :ok, state}
      {:ok, _other} -> {:reply, {:error, :effect_identity_conflict}, state}
    end
  end

  defp availability(true), do: :available
  defp availability(false), do: :unavailable
  defp availability(value) when value in [:available, :unavailable, :uncertain_once], do: value

  defp address(jido), do: {:via, Registry, {Jido.Instance.Names.registry(jido), {__MODULE__, :sink}}}
end
