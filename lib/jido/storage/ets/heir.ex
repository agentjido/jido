defmodule Jido.Storage.ETS.Heir do
  @moduledoc """
  Process heir for ETS tables managed by `Jido.Storage.ETS.Owner`.

  If the owner process crashes, ETS transfers table ownership to this process
  instead of deleting the table. This preserves in-memory state until the system
  can recover.
  """

  use GenServer

  @type transfer_info :: %{
          table: atom(),
          from: pid(),
          data: term(),
          transferred_at: integer()
        }

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Returns ETS transfer events observed by the heir.
  """
  @spec transfers() :: [transfer_info()]
  def transfers do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) ->
        GenServer.call(pid, :transfers)

      nil ->
        []
    end
  end

  @impl true
  def init(_state) do
    {:ok, []}
  end

  @impl true
  def handle_call(:transfers, _from, transfers) do
    {:reply, Enum.reverse(transfers), transfers}
  end

  @impl true
  def handle_info({:"ETS-TRANSFER", table, from_pid, data}, transfers) when is_atom(table) do
    event = %{
      table: table,
      from: from_pid,
      data: data,
      transferred_at: System.system_time(:millisecond)
    }

    {:noreply, [event | transfers]}
  end

  def handle_info(_message, transfers) do
    {:noreply, transfers}
  end
end
