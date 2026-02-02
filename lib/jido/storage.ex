defmodule Jido.Storage do
  @moduledoc """
  Unified storage behaviour for agent checkpoints and thread journals.

  Implementations handle both:
  - **Checkpoints**: key-value overwrite semantics for agent state snapshots
  - **Journals**: append-only thread entries with sequence ordering

  ## Built-in Adapters

  | Adapter | Durability | Use Case |
  |---------|------------|----------|
  | `Jido.Storage.ETS` | Ephemeral | Development, testing |

  ## Implementing Custom Adapters

  Implement all 6 callbacks to create a custom storage adapter:

      defmodule MyApp.Storage do
        @behaviour Jido.Storage

        @impl true
        def get_checkpoint(key, opts), do: ...

        @impl true
        def put_checkpoint(key, data, opts), do: ...

        @impl true
        def delete_checkpoint(key, opts), do: ...

        @impl true
        def load_thread(thread_id, opts), do: ...

        @impl true
        def append_thread(thread_id, entries, opts), do: ...

        @impl true
        def delete_thread(thread_id, opts), do: ...
      end

  ## Concurrency

  The `append_thread/3` callback accepts an `:expected_rev` option for
  optimistic concurrency control. Implementations should reject appends
  when the current revision doesn't match the expected value.
  """

  alias Jido.Thread
  alias Jido.Thread.Entry

  @doc """
  Retrieve a checkpoint by key.

  Returns `{:ok, data}` if found, `:not_found` if the key doesn't exist.
  """
  @callback get_checkpoint(key :: term(), opts :: keyword()) ::
              {:ok, term()} | :not_found | {:error, term()}

  @doc """
  Store a checkpoint, overwriting any existing value for the key.
  """
  @callback put_checkpoint(key :: term(), data :: term(), opts :: keyword()) ::
              :ok | {:error, term()}

  @doc """
  Delete a checkpoint by key.

  Returns `:ok` even if the key didn't exist.
  """
  @callback delete_checkpoint(key :: term(), opts :: keyword()) ::
              :ok | {:error, term()}

  @doc """
  Load a thread by ID, reconstructing from stored entries.

  Returns `{:ok, thread}` if entries exist, `:not_found` if the thread
  has no entries.
  """
  @callback load_thread(thread_id :: String.t(), opts :: keyword()) ::
              {:ok, Thread.t()} | :not_found | {:error, term()}

  @doc """
  Append entries to a thread.

  ## Options

  - `:expected_rev` - If provided, the append should fail with
    `{:error, :conflict}` if the current thread revision doesn't match.
  - `:metadata` - Thread metadata to set (typically only for new threads).

  Returns `{:ok, updated_thread}` on success.
  """
  @callback append_thread(thread_id :: String.t(), entries :: [Entry.t()], opts :: keyword()) ::
              {:ok, Thread.t()} | {:error, term()}

  @doc """
  Delete a thread and all its entries.

  Returns `:ok` even if the thread didn't exist.
  """
  @callback delete_thread(thread_id :: String.t(), opts :: keyword()) ::
              :ok | {:error, term()}

  @doc """
  Normalize a storage configuration to `{module, opts}` tuple.

  ## Examples

      iex> Jido.Storage.normalize_storage(Jido.Storage.ETS)
      {Jido.Storage.ETS, []}

      iex> Jido.Storage.normalize_storage({Jido.Storage.File, path: "priv/jido"})
      {Jido.Storage.File, [path: "priv/jido"]}
  """
  @spec normalize_storage(module() | {module(), keyword()}) :: {module(), keyword()}
  def normalize_storage({mod, opts}) when is_atom(mod) and is_list(opts), do: {mod, opts}
  def normalize_storage(mod) when is_atom(mod), do: {mod, []}
end
