defmodule Jido.RuntimeStore do
  @moduledoc false

  use GenServer

  @call_timeout Application.compile_env(:jido, :runtime_store_timeout, 5_000)

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

  @doc false
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

  @doc false
  @spec get(atom(), hive(), key(), value()) :: value()
  def get(instance, hive, key, default \\ nil) when is_atom(instance) do
    case fetch(instance, hive, key) do
      {:ok, value} -> value
      :error -> default
    end
  end

  @doc false
  @spec fetch(atom(), hive(), key()) :: {:ok, value()} | :error
  def fetch(instance, hive, key) when is_atom(instance) do
    call(instance, {:fetch, hive, key}, :error)
  end

  @doc false
  @spec put(atom(), hive(), key(), value()) :: :ok | {:error, term()}
  def put(instance, hive, key, value) when is_atom(instance) do
    call(instance, {:put, hive, key, value}, {:error, :not_running}, {:error, :timeout})
  end

  @doc false
  @spec delete(atom(), hive(), key()) :: :ok | {:error, term()}
  def delete(instance, hive, key) when is_atom(instance) do
    call(instance, {:delete, hive, key}, {:error, :not_running}, {:error, :timeout})
  end

  @doc false
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

  defp call(instance, request, fallback, timeout_fallback \\ nil) do
    server = Jido.runtime_store_name(instance)
    timeout_fallback = if is_nil(timeout_fallback), do: fallback, else: timeout_fallback

    try do
      GenServer.call(server, request, @call_timeout)
    catch
      :exit, {:noproc, _} -> fallback
      :exit, {:normal, _} -> fallback
      :exit, {:timeout, {GenServer, :call, _details}} -> timeout_fallback
    end
  end
end
