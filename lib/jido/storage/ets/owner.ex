defmodule Jido.Storage.ETS.Owner do
  @moduledoc """
  Dedicated owner process for storage ETS tables.

  All tables created through this module are owned by this process and configured
  with `Jido.Storage.ETS.Heir` as ETS heir, ensuring table continuity if the owner
  crashes.
  """

  use GenServer

  @default_table_opts [:named_table, :public, {:read_concurrency, true}]

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Ensures an ETS table exists under the owner process.

  `extra_opts` typically contains table type options like `:set` or `:ordered_set`.
  """
  @spec ensure_table(atom(), keyword() | [term()]) :: :ok | {:error, term()}
  def ensure_table(table, extra_opts \\ [])

  def ensure_table(table, extra_opts) when is_atom(table) and is_list(extra_opts) do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) ->
        GenServer.call(pid, {:ensure_table, table, extra_opts})

      nil ->
        {:error, :owner_not_running}
    end
  catch
    :exit, {:noproc, _} -> {:error, :owner_not_running}
    :exit, {:normal, _} -> {:error, :owner_not_running}
    :exit, {:shutdown, _} -> {:error, :owner_not_running}
  end

  def ensure_table(_table, _extra_opts), do: {:error, :invalid_table_name}

  @impl true
  def init(_state) do
    {:ok, %{heir: Process.whereis(Jido.Storage.ETS.Heir)}}
  end

  @impl true
  def handle_call({:ensure_table, table, extra_opts}, _from, state) do
    {:reply, do_ensure_table(table, extra_opts, state.heir), state}
  end

  defp do_ensure_table(table, extra_opts, heir_pid) do
    case :ets.whereis(table) do
      :undefined ->
        create_table(table, extra_opts, heir_pid)

      _table_ref ->
        maybe_set_heir(table, heir_pid)
        :ok
    end
  rescue
    ArgumentError -> :ok
  end

  defp create_table(table, extra_opts, heir_pid) do
    _table_ref =
      :ets.new(
        table,
        @default_table_opts ++ List.wrap(extra_opts) ++ heir_option(table, heir_pid)
      )

    :ok
  rescue
    ArgumentError ->
      # Table may have been created concurrently in a race window.
      :ok
  end

  defp maybe_set_heir(_table, heir_pid) when not is_pid(heir_pid), do: :ok

  defp maybe_set_heir(table, heir_pid) when is_pid(heir_pid) do
    if :ets.info(table, :owner) == self() do
      :ets.setopts(table, {:heir, heir_pid, heir_data(table)})
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  defp heir_option(_table, heir_pid) when not is_pid(heir_pid), do: []
  defp heir_option(table, heir_pid), do: [{:heir, heir_pid, heir_data(table)}]

  defp heir_data(table), do: {:jido_storage_ets_table, table}
end
