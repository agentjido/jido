defmodule Jido.Thread.Store do
  @moduledoc """
  Persistence behavior for Thread storage.

  Store operations return updated store state to preserve purity
  for adapters that don't use external processes.

  ## Example

      {:ok, store} = Thread.Store.new()

      thread = Thread.new(id: "t1")
      {:ok, store} = Thread.Store.save(store, thread)

      {:ok, store, loaded} = Thread.Store.load(store, "t1")
  """

  alias Jido.Thread
  alias Jido.Thread.Entry

  @type adapter_state :: term()
  @type t :: %__MODULE__{adapter: module(), adapter_state: adapter_state()}

  defstruct [:adapter, :adapter_state]

  @doc "Initialize adapter state"
  @callback init(opts :: keyword()) :: {:ok, adapter_state()} | {:error, term()}

  @doc "Load thread by ID"
  @callback load(adapter_state(), thread_id :: String.t()) ::
              {:ok, adapter_state(), Thread.t()} | {:error, adapter_state(), :not_found | term()}

  @doc "Save thread"
  @callback save(adapter_state(), Thread.t()) ::
              {:ok, adapter_state()} | {:error, adapter_state(), term()}

  @doc "Append entries to thread"
  @callback append(adapter_state(), thread_id :: String.t(), [Entry.t()]) ::
              {:ok, adapter_state(), Thread.t()} | {:error, adapter_state(), term()}

  @doc "Create new store with adapter"
  @spec new(module(), keyword()) :: {:ok, t()} | {:error, term()}
  def new(adapter \\ __MODULE__.Adapters.InMemory, opts \\ []) do
    case adapter.init(opts) do
      {:ok, state} -> {:ok, %__MODULE__{adapter: adapter, adapter_state: state}}
      {:error, _} = error -> error
    end
  end

  @doc "Load thread from store"
  @spec load(t(), String.t()) :: {:ok, t(), Thread.t()} | {:error, t(), term()}
  def load(%__MODULE__{adapter: adapter, adapter_state: state} = store, thread_id) do
    case adapter.load(state, thread_id) do
      {:ok, new_state, thread} -> {:ok, %{store | adapter_state: new_state}, thread}
      {:error, new_state, reason} -> {:error, %{store | adapter_state: new_state}, reason}
    end
  end

  @doc "Save thread to store"
  @spec save(t(), Thread.t()) :: {:ok, t()} | {:error, t(), term()}
  def save(%__MODULE__{adapter: adapter, adapter_state: state} = store, thread) do
    case adapter.save(state, thread) do
      {:ok, new_state} -> {:ok, %{store | adapter_state: new_state}}
      {:error, new_state, reason} -> {:error, %{store | adapter_state: new_state}, reason}
    end
  end

  @doc "Append entries to thread in store"
  @spec append(t(), String.t(), Entry.t() | [Entry.t()]) ::
          {:ok, t(), Thread.t()} | {:error, t(), term()}
  def append(%__MODULE__{adapter: adapter, adapter_state: state} = store, thread_id, entries) do
    entries = List.wrap(entries)

    case adapter.append(state, thread_id, entries) do
      {:ok, new_state, thread} -> {:ok, %{store | adapter_state: new_state}, thread}
      {:error, new_state, reason} -> {:error, %{store | adapter_state: new_state}, reason}
    end
  end

  @doc "Delete thread from store"
  @spec delete(t(), String.t()) :: {:ok, t()} | {:error, t(), term()}
  def delete(%__MODULE__{adapter: adapter, adapter_state: state} = store, thread_id) do
    if function_exported?(adapter, :delete, 2) do
      case adapter.delete(state, thread_id) do
        {:ok, new_state} -> {:ok, %{store | adapter_state: new_state}}
        {:error, new_state, reason} -> {:error, %{store | adapter_state: new_state}, reason}
      end
    else
      {:error, store, :not_implemented}
    end
  end

  @doc "List all thread IDs in store"
  @spec list(t()) :: {:ok, t(), [String.t()]} | {:error, t(), term()}
  def list(%__MODULE__{adapter: adapter, adapter_state: state} = store) do
    if function_exported?(adapter, :list, 1) do
      case adapter.list(state) do
        {:ok, new_state, ids} -> {:ok, %{store | adapter_state: new_state}, ids}
        {:error, new_state, reason} -> {:error, %{store | adapter_state: new_state}, reason}
      end
    else
      {:error, store, :not_implemented}
    end
  end
end
