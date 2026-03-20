defmodule Jido.RuntimeStore do
  @moduledoc """
  Instance-scoped runtime key/value store for mutable Jido coordination state.

  `RuntimeStore` is an internal control-plane store owned by each Jido instance.
  It backs ephemeral runtime data that needs a stable home outside individual
  agent processes, such as logical parent-child relationship bindings.

  The ETS table itself is owned by the Jido instance supervisor, while the
  `RuntimeStore` process provides the logical API. That lets the table survive
  `RuntimeStore` process restarts without making it durable beyond the life of
  the owning Jido instance.

  Values are organized into named hives so unrelated runtime concerns can share
  the same store without colliding:

      :ok = Jido.RuntimeStore.put(MyApp.Jido, :relationships, "child-1", %{parent_id: "p-1"})
      {:ok, binding} = Jido.RuntimeStore.fetch(MyApp.Jido, :relationships, "child-1")
      :ok = Jido.RuntimeStore.delete(MyApp.Jido, :relationships, "child-1")

  The store is intentionally ephemeral. It is reset when the owning Jido
  instance stops or restarts.
  """

  use GenServer

  @type hive :: term()
  @type key :: term()
  @type value :: term()
  @type state :: %{table: atom()}

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)

    %{
      id: name,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 5_000,
      type: :worker
    }
  end

  @doc """
  Starts a RuntimeStore process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc false
  @spec ensure_table(atom()) :: :ok
  def ensure_table(table) when is_atom(table) do
    case :ets.whereis(table) do
      :undefined ->
        _ =
          :ets.new(table, [
            :named_table,
            :set,
            :public,
            read_concurrency: true,
            write_concurrency: true
          ])

        :ok

      _tid ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Returns a value from the given hive, or `default` when no value exists.
  """
  @spec get(atom(), hive(), key(), value()) :: value()
  def get(instance, hive, key, default \\ nil) when is_atom(instance) do
    case fetch(instance, hive, key) do
      {:ok, value} -> value
      :error -> default
    end
  end

  @doc """
  Fetches a value from the given hive.

  Returns `{:ok, value}` when present, or `:error` when the key or store is
  unavailable.
  """
  @spec fetch(atom(), hive(), key()) :: {:ok, value()} | :error
  def fetch(instance, hive, key) when is_atom(instance) do
    case call(instance, {:fetch, hive, key}, :error) do
      {:ok, value} -> {:ok, value}
      :error -> :error
    end
  end

  @doc """
  Stores a value in the given hive.
  """
  @spec put(atom(), hive(), key(), value()) :: :ok | {:error, term()}
  def put(instance, hive, key, value) when is_atom(instance) do
    call(instance, {:put, hive, key, value}, {:error, :not_running})
  end

  @doc """
  Deletes a value from the given hive.
  """
  @spec delete(atom(), hive(), key()) :: :ok | {:error, term()}
  def delete(instance, hive, key) when is_atom(instance) do
    call(instance, {:delete, hive, key}, {:error, :not_running})
  end

  @doc """
  Lists all `{key, value}` entries in the given hive.
  """
  @spec list(atom(), hive()) :: [{key(), value()}]
  def list(instance, hive) when is_atom(instance) do
    call(instance, {:list, hive}, [])
  end

  @impl true
  def init(opts) do
    table = Keyword.fetch!(opts, :name)

    case :ets.whereis(table) do
      :undefined -> {:stop, {:runtime_store_table_missing, table}}
      _tid -> {:ok, %{table: table}}
    end
  end

  @impl true
  def handle_call({:fetch, hive, key}, _from, %{table: table} = state) do
    reply =
      case :ets.lookup(table, {hive, key}) do
        [{{^hive, ^key}, value}] -> {:ok, value}
        [] -> :error
      end

    {:reply, reply, state}
  end

  def handle_call({:put, hive, key, value}, _from, %{table: table} = state) do
    true = :ets.insert(table, {{hive, key}, value})
    {:reply, :ok, state}
  end

  def handle_call({:delete, hive, key}, _from, %{table: table} = state) do
    true = :ets.delete(table, {hive, key})
    {:reply, :ok, state}
  end

  def handle_call({:list, hive}, _from, %{table: table} = state) do
    entries =
      :ets.select(table, [
        {{{hive, :"$1"}, :"$2"}, [], [{{:"$1", :"$2"}}]}
      ])

    {:reply, entries, state}
  end

  defp call(instance, request, fallback) do
    server = Jido.runtime_store_name(instance)

    try do
      case GenServer.whereis(server) do
        nil ->
          fallback

        _pid ->
          GenServer.call(server, request)
      end
    catch
      :exit, {:noproc, _} -> fallback
      :exit, {:normal, _} -> fallback
    end
  end
end
