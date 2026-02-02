defmodule Jido.Thread.Store.Adapters.InMemory do
  @moduledoc """
  Pure in-memory adapter storing threads in a map.

  No external processes - state is carried in adapter_state.
  Thread is auto-created on append if it doesn't exist.
  """

  @behaviour Jido.Thread.Store

  alias Jido.Thread

  @impl true
  def init(_opts) do
    {:ok, %{threads: %{}}}
  end

  @impl true
  def load(%{threads: threads} = state, thread_id) do
    case Map.get(threads, thread_id) do
      nil -> {:error, state, :not_found}
      thread -> {:ok, state, thread}
    end
  end

  @impl true
  def save(%{threads: threads} = state, %Thread{id: id} = thread) do
    {:ok, %{state | threads: Map.put(threads, id, thread)}}
  end

  @impl true
  def append(%{threads: threads} = state, thread_id, entries) do
    thread = Map.get(threads, thread_id) || Thread.new(id: thread_id)
    thread = Thread.append(thread, entries)
    new_state = %{state | threads: Map.put(threads, thread_id, thread)}
    {:ok, new_state, thread}
  end

  @doc "Delete a thread"
  @spec delete(%{threads: map()}, String.t()) :: {:ok, %{threads: map()}}
  def delete(%{threads: threads} = state, thread_id) do
    {:ok, %{state | threads: Map.delete(threads, thread_id)}}
  end

  @doc "List all thread IDs"
  @spec list(%{threads: map()}) :: {:ok, %{threads: map()}, [String.t()]}
  def list(%{threads: threads} = state) do
    {:ok, state, Map.keys(threads)}
  end
end
