defmodule JidoTest.RelationshipFaultStore do
  @moduledoc false
  use GenServer

  def start(table) do
    GenServer.start(__MODULE__, table, name: table)
  end

  def rejected(pid), do: GenServer.call(pid, :rejected)

  @impl true
  def init(table) do
    if :ets.whereis(table) == :undefined,
      do: {:stop, :table_missing},
      else: {:ok, %{table: table, rejected: 0}}
  end

  def handle_call(:rejected, _from, state), do: {:reply, state.rejected, state}

  @impl true
  def handle_call({:fetch, hive, key}, _from, %{table: table} = state) do
    reply =
      case :ets.lookup(table, {hive, key}) do
        [{{^hive, ^key}, value}] -> {:ok, value}
        [] -> :error
      end

    {:reply, reply, state}
  end

  def handle_call({:put, :agent_relationships, _key, _value}, _from, state),
    do: {:reply, {:error, :not_running}, %{state | rejected: state.rejected + 1}}

  def handle_call({:put, hive, key, value}, _from, %{table: table} = state) do
    true = :ets.insert(table, {{hive, key}, value})
    {:reply, :ok, state}
  end

  def handle_call({:delete, hive, key}, _from, %{table: table} = state) do
    true = :ets.delete(table, {hive, key})
    {:reply, :ok, state}
  end

  def handle_call({:list, hive}, _from, %{table: table} = state) do
    values = for {{^hive, key}, value} <- :ets.tab2list(table), do: {key, value}
    {:reply, values, state}
  end
end
