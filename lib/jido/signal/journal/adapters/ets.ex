defmodule Jido.Signal.Journal.Adapters.ETS do
  @moduledoc """
  ETS-based implementation of the Journal persistence behavior.
  Uses separate ETS tables for signals, causes, effects, and conversations.

  ## Configuration
  The adapter requires a prefix for table names to allow multiple instances:

      {:ok, _pid} = Jido.Signal.Journal.Adapters.ETS.start_link("my_journal_")
      {:ok, journal} = Jido.Signal.Journal.new(Jido.Signal.Journal.Adapters.ETS)

  This will create tables with names:
    - :my_journal_signals
    - :my_journal_causes
    - :my_journal_effects
    - :my_journal_conversations
  """
  @behaviour Jido.Signal.Journal.Persistence
  use GenServer

  defstruct [:signals_table, :causes_table, :effects_table, :conversations_table]

  @type t :: %__MODULE__{
          signals_table: atom(),
          causes_table: atom(),
          effects_table: atom(),
          conversations_table: atom()
        }

  # Client API

  @doc """
  Starts the ETS adapter with the given table name prefix.
  """
  def start_link(prefix) when is_binary(prefix) do
    # Generate a unique name for this instance's GenServer
    name = String.to_atom("#{prefix}process_#{System.unique_integer([:positive, :monotonic])}")
    GenServer.start_link(__MODULE__, prefix, name: name)
  end

  @impl Jido.Signal.Journal.Persistence
  def init do
    # Generate a unique prefix for this instance
    prefix = "journal_#{System.unique_integer([:positive, :monotonic])}_"

    case start_link(prefix) do
      {:ok, pid} -> {:ok, pid}
      error -> error
    end
  end

  @impl Jido.Signal.Journal.Persistence
  def put_signal(signal, pid) do
    GenServer.call(pid, {:put_signal, signal})
  end

  @impl Jido.Signal.Journal.Persistence
  def get_signal(signal_id, pid) do
    GenServer.call(pid, {:get_signal, signal_id})
  end

  @impl Jido.Signal.Journal.Persistence
  def put_cause(cause_id, effect_id, pid) do
    GenServer.call(pid, {:put_cause, cause_id, effect_id})
  end

  @impl Jido.Signal.Journal.Persistence
  def get_effects(signal_id, pid) do
    GenServer.call(pid, {:get_effects, signal_id})
  end

  @impl Jido.Signal.Journal.Persistence
  def get_cause(signal_id, pid) do
    GenServer.call(pid, {:get_cause, signal_id})
  end

  @impl Jido.Signal.Journal.Persistence
  def put_conversation(conversation_id, signal_id, pid) do
    GenServer.call(pid, {:put_conversation, conversation_id, signal_id})
  end

  @impl Jido.Signal.Journal.Persistence
  def get_conversation(conversation_id, pid) do
    GenServer.call(pid, {:get_conversation, conversation_id})
  end

  @doc """
  Gets all signals in the journal.
  """
  def get_all_signals(pid) do
    GenServer.call(pid, :get_all_signals)
  end

  @doc """
  Cleans up all ETS tables used by this adapter instance.
  """
  def cleanup(pid) do
    GenServer.call(pid, :cleanup)
  end

  # Server Callbacks

  @impl GenServer
  def init(prefix) do
    adapter = %__MODULE__{
      signals_table:
        String.to_atom("#{prefix}signals_#{System.unique_integer([:positive, :monotonic])}"),
      causes_table:
        String.to_atom("#{prefix}causes_#{System.unique_integer([:positive, :monotonic])}"),
      effects_table:
        String.to_atom("#{prefix}effects_#{System.unique_integer([:positive, :monotonic])}"),
      conversations_table:
        String.to_atom("#{prefix}conversations_#{System.unique_integer([:positive, :monotonic])}")
    }

    # Create tables if they don't exist
    tables = [
      {:signals, adapter.signals_table, [:set, :public, :named_table]},
      {:causes, adapter.causes_table, [:set, :public, :named_table]},
      {:effects, adapter.effects_table, [:set, :public, :named_table]},
      {:conversations, adapter.conversations_table, [:set, :public, :named_table]}
    ]

    Enum.each(tables, fn {_name, table, opts} ->
      case :ets.whereis(table) do
        :undefined ->
          :ets.new(table, opts)

        _ref ->
          :ok
      end
    end)

    {:ok, adapter}
  end

  @impl GenServer
  def handle_call({:put_signal, signal}, _from, adapter) do
    true = :ets.insert(adapter.signals_table, {signal.id, signal})
    {:reply, :ok, adapter}
  end

  @impl GenServer
  def handle_call({:get_signal, signal_id}, _from, adapter) do
    reply =
      case :ets.lookup(adapter.signals_table, signal_id) do
        [{^signal_id, signal}] -> {:ok, signal}
        [] -> {:error, :not_found}
      end

    {:reply, reply, adapter}
  end

  @impl GenServer
  def handle_call({:put_cause, cause_id, effect_id}, _from, adapter) do
    # Update causes
    effects =
      case :ets.lookup(adapter.causes_table, cause_id) do
        [{^cause_id, existing}] -> MapSet.put(existing, effect_id)
        [] -> MapSet.new([effect_id])
      end

    true = :ets.insert(adapter.causes_table, {cause_id, effects})

    # Update effects
    causes =
      case :ets.lookup(adapter.effects_table, effect_id) do
        [{^effect_id, existing}] -> MapSet.put(existing, cause_id)
        [] -> MapSet.new([cause_id])
      end

    true = :ets.insert(adapter.effects_table, {effect_id, causes})
    {:reply, :ok, adapter}
  end

  @impl GenServer
  def handle_call({:get_effects, signal_id}, _from, adapter) do
    effects =
      case :ets.lookup(adapter.causes_table, signal_id) do
        [{^signal_id, effects}] -> effects
        [] -> MapSet.new()
      end

    {:reply, {:ok, effects}, adapter}
  end

  @impl GenServer
  def handle_call({:get_cause, signal_id}, _from, adapter) do
    reply =
      case :ets.lookup(adapter.effects_table, signal_id) do
        [{^signal_id, causes}] ->
          case MapSet.to_list(causes) do
            [cause_id | _] -> {:ok, cause_id}
            [] -> {:error, :not_found}
          end

        [] ->
          {:error, :not_found}
      end

    {:reply, reply, adapter}
  end

  @impl GenServer
  def handle_call({:put_conversation, conversation_id, signal_id}, _from, adapter) do
    signals =
      case :ets.lookup(adapter.conversations_table, conversation_id) do
        [{^conversation_id, existing}] -> MapSet.put(existing, signal_id)
        [] -> MapSet.new([signal_id])
      end

    true = :ets.insert(adapter.conversations_table, {conversation_id, signals})
    {:reply, :ok, adapter}
  end

  @impl GenServer
  def handle_call({:get_conversation, conversation_id}, _from, adapter) do
    signals =
      case :ets.lookup(adapter.conversations_table, conversation_id) do
        [{^conversation_id, signals}] -> signals
        [] -> MapSet.new()
      end

    {:reply, {:ok, signals}, adapter}
  end

  @impl GenServer
  def handle_call(:get_all_signals, _from, adapter) do
    signals =
      :ets.tab2list(adapter.signals_table)
      |> Enum.map(fn {_id, signal} -> signal end)

    {:reply, signals, adapter}
  end

  @impl GenServer
  def handle_call(:cleanup, _from, adapter) do
    [
      adapter.signals_table,
      adapter.causes_table,
      adapter.effects_table,
      adapter.conversations_table
    ]
    |> Enum.each(fn table ->
      case :ets.whereis(table) do
        :undefined -> :ok
        _ref -> :ets.delete(table)
      end
    end)

    {:reply, :ok, adapter}
  end
end
