defmodule Jido.Signal.Journal.Adapters.ETSTest do
  use ExUnit.Case, async: true
  alias Jido.Signal
  alias Jido.Signal.Journal.Adapters.ETS

  # Helper function to create test signals with unique IDs
  defp create_test_signal(opts \\ []) do
    id = Jido.Signal.ID.generate!()
    type = Keyword.get(opts, :type, "test")
    source = Keyword.get(opts, :source, "test")
    subject = Keyword.get(opts, :subject, "test")
    time = Keyword.get(opts, :time, DateTime.utc_now())

    %Signal{
      id: id,
      type: type,
      source: source,
      time: time,
      subject: subject
    }
  end

  setup do
    # Generate a unique prefix for this test run
    prefix = "test_journal_#{System.unique_integer([:positive, :monotonic])}_"

    # Start the ETS adapter
    {:ok, pid} = ETS.start_link(prefix)

    on_exit(fn ->
      if Process.alive?(pid) do
        # Ensure cleanup happens before process termination
        :ok = ETS.cleanup(pid)
        Process.exit(pid, :normal)
      end
    end)

    {:ok, pid: pid}
  end

  test "init creates ETS tables", %{pid: pid} do
    # Get the adapter state from the GenServer
    adapter = :sys.get_state(pid)
    assert :ets.whereis(adapter.signals_table) != :undefined
    assert :ets.whereis(adapter.causes_table) != :undefined
    assert :ets.whereis(adapter.effects_table) != :undefined
    assert :ets.whereis(adapter.conversations_table) != :undefined
  end

  test "put_signal/2 and get_signal/2", %{pid: pid} do
    signal = create_test_signal()
    assert :ok = ETS.put_signal(signal, pid)
    assert {:ok, ^signal} = ETS.get_signal(signal.id, pid)
  end

  test "get_signal/2 returns error for non-existent signal", %{pid: pid} do
    assert {:error, :not_found} = ETS.get_signal("non_existent", pid)
  end

  test "put_cause/3 and get_cause/2", %{pid: pid} do
    signal1 = create_test_signal()
    # Ensure different timestamps
    Process.sleep(10)
    signal2 = create_test_signal()

    :ok = ETS.put_signal(signal1, pid)
    :ok = ETS.put_signal(signal2, pid)
    :ok = ETS.put_cause(signal1.id, signal2.id, pid)

    {:ok, cause_id} = ETS.get_cause(signal2.id, pid)
    assert cause_id == signal1.id
  end

  test "get_effects/2", %{pid: pid} do
    signal1 = create_test_signal()
    # Ensure different timestamps
    Process.sleep(10)
    signal2 = create_test_signal()

    :ok = ETS.put_signal(signal1, pid)
    :ok = ETS.put_signal(signal2, pid)
    :ok = ETS.put_cause(signal1.id, signal2.id, pid)

    {:ok, effects} = ETS.get_effects(signal1.id, pid)
    assert MapSet.member?(effects, signal2.id)
  end

  test "put_conversation/3 and get_conversation/2", %{pid: pid} do
    signal = create_test_signal()
    conversation_id = "test_conv_#{System.unique_integer([:positive, :monotonic])}"

    :ok = ETS.put_signal(signal, pid)
    :ok = ETS.put_conversation(conversation_id, signal.id, pid)

    {:ok, signals} = ETS.get_conversation(conversation_id, pid)
    assert MapSet.member?(signals, signal.id)
  end

  test "get_all_signals/1", %{pid: pid} do
    signal1 = create_test_signal()
    # Ensure different timestamps
    Process.sleep(10)
    signal2 = create_test_signal()

    :ok = ETS.put_signal(signal1, pid)
    :ok = ETS.put_signal(signal2, pid)

    signals = ETS.get_all_signals(pid)
    assert length(signals) == 2
    assert Enum.any?(signals, &(&1.id == signal1.id))
    assert Enum.any?(signals, &(&1.id == signal2.id))
  end

  test "cleanup/1 removes all tables", %{pid: pid} do
    # Get the adapter state from the GenServer
    adapter = :sys.get_state(pid)
    :ok = ETS.cleanup(pid)

    # Wait briefly for table deletion
    :timer.sleep(10)
    assert :ets.whereis(adapter.signals_table) == :undefined
    assert :ets.whereis(adapter.causes_table) == :undefined
    assert :ets.whereis(adapter.effects_table) == :undefined
    assert :ets.whereis(adapter.conversations_table) == :undefined
  end

  test "multiple adapters can coexist" do
    prefix1 = "test_journal_#{System.unique_integer([:positive, :monotonic])}_"
    prefix2 = "test_journal_#{System.unique_integer([:positive, :monotonic])}_"

    {:ok, pid1} = ETS.start_link(prefix1)
    {:ok, pid2} = ETS.start_link(prefix2)

    signal1 = create_test_signal()
    :ok = ETS.put_signal(signal1, pid1)

    # Get the adapter states from the GenServers
    adapter1 = :sys.get_state(pid1)
    adapter2 = :sys.get_state(pid2)

    # Verify tables exist for both adapters
    assert :ets.whereis(adapter1.signals_table) != :undefined
    assert :ets.whereis(adapter2.signals_table) != :undefined

    # Clean up both adapters
    :ok = ETS.cleanup(pid1)
    :ok = ETS.cleanup(pid2)

    # Wait briefly for table deletion
    :timer.sleep(10)
    assert :ets.whereis(adapter1.signals_table) == :undefined
    assert :ets.whereis(adapter2.signals_table) == :undefined

    Process.exit(pid1, :normal)
    Process.exit(pid2, :normal)
  end
end
