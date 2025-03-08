defmodule Jido.Signal.Journal.Adapters.InMemory do
  @moduledoc """
  In-memory implementation of the Journal persistence behavior.
  Uses Agent to maintain state.
  """
  @behaviour Jido.Signal.Journal.Persistence

  use Agent

  @impl true
  def init do
    case Agent.start_link(
           fn ->
             %{
               signals: %{},
               causes: %{},
               effects: %{},
               conversations: %{}
             }
           end,
           name: __MODULE__
         ) do
      {:ok, _pid} -> :ok
      error -> error
    end
  end

  @impl true
  def put_signal(signal, _pid \\ nil) do
    Agent.update(__MODULE__, fn state ->
      put_in(state, [:signals, signal.id], signal)
    end)
  end

  @impl true
  def get_signal(signal_id, _pid \\ nil) do
    case Agent.get(__MODULE__, fn state -> get_in(state, [:signals, signal_id]) end) do
      nil -> {:error, :not_found}
      signal -> {:ok, signal}
    end
  end

  @impl true
  def put_cause(cause_id, effect_id, _pid \\ nil) do
    Agent.update(__MODULE__, fn state ->
      state
      |> update_in([:causes, cause_id], &MapSet.put(&1 || MapSet.new(), effect_id))
      |> update_in([:effects, effect_id], &MapSet.put(&1 || MapSet.new(), cause_id))
    end)
  end

  @impl true
  def get_effects(signal_id, _pid \\ nil) do
    {:ok,
     Agent.get(__MODULE__, fn state -> get_in(state, [:causes, signal_id]) || MapSet.new() end)}
  end

  @impl true
  def get_cause(signal_id, _pid \\ nil) do
    case Agent.get(__MODULE__, fn state -> get_in(state, [:effects, signal_id]) end) do
      nil -> {:error, :not_found}
      effects -> {:ok, MapSet.to_list(effects) |> List.first()}
    end
  end

  @impl true
  def put_conversation(conversation_id, signal_id, _pid \\ nil) do
    Agent.update(__MODULE__, fn state ->
      update_in(
        state,
        [:conversations, conversation_id],
        &MapSet.put(&1 || MapSet.new(), signal_id)
      )
    end)
  end

  @impl true
  def get_conversation(conversation_id, _pid \\ nil) do
    {:ok,
     Agent.get(__MODULE__, fn state ->
       get_in(state, [:conversations, conversation_id]) || MapSet.new()
     end)}
  end

  @doc """
  Gets all signals in the journal.
  """
  def get_all_signals do
    Agent.get(__MODULE__, fn state ->
      state.signals
      |> Map.values()
    end)
  end
end
