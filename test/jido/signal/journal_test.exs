defmodule Jido.Signal.JournalTest do
  use ExUnit.Case, async: true
  alias Jido.Signal
  alias Jido.Signal.Journal

  setup do
    on_exit(fn ->
      # Clean up any ETS adapter state
      if journal = Process.get(:current_journal) do
        if journal.adapter == Jido.Signal.Journal.Adapters.ETS and
             is_pid(journal.adapter_pid) and
             Process.alive?(journal.adapter_pid) do
          Jido.Signal.Journal.Adapters.ETS.cleanup(journal.adapter_pid)
          Process.exit(journal.adapter_pid, :normal)
        end

        Process.delete(:current_journal)
      end
    end)

    :ok
  end

  describe "new/0" do
    test "new/0 creates an empty journal" do
      journal = Journal.new()
      Process.put(:current_journal, journal)
      assert %Journal{} = journal
    end
  end

  describe "record/3" do
    test "records a signal in the journal" do
      journal = Journal.new()
      Process.put(:current_journal, journal)
      signal = Signal.new!(type: "test.event", source: "/test")
      {:ok, journal} = Journal.record(journal, signal)

      signals = Journal.query(journal, %{})
      assert length(signals) == 1
      assert hd(signals).id == signal.id
    end

    test "groups signals by conversation (subject)" do
      journal = Journal.new()
      Process.put(:current_journal, journal)
      signal1 = Signal.new!(type: "test.event", source: "/test", subject: "conv1")
      signal2 = Signal.new!(type: "test.event", source: "/test", subject: "conv1")
      signal3 = Signal.new!(type: "test.event", source: "/test", subject: "conv2")

      {:ok, journal} = Journal.record(journal, signal1)
      {:ok, journal} = Journal.record(journal, signal2)
      {:ok, journal} = Journal.record(journal, signal3)

      conv1_signals = Journal.get_conversation(journal, "conv1")
      conv2_signals = Journal.get_conversation(journal, "conv2")

      assert length(conv1_signals) == 2
      assert length(conv2_signals) == 1
      assert Enum.all?(conv1_signals, &(&1.subject == "conv1"))
      assert Enum.all?(conv2_signals, &(&1.subject == "conv2"))
    end

    test "tracks causality between signals" do
      journal = Journal.new()
      signal1 = Signal.new!(type: "test.event", source: "/test")
      signal2 = Signal.new!(type: "test.event", source: "/test")
      signal3 = Signal.new!(type: "test.event", source: "/test")

      {:ok, journal} = Journal.record(journal, signal1)
      {:ok, journal} = Journal.record(journal, signal2, signal1.id)
      {:ok, journal} = Journal.record(journal, signal3, signal2.id)

      # Check effects (forward causality)
      effects1 = Journal.get_effects(journal, signal1.id)
      effects2 = Journal.get_effects(journal, signal2.id)
      effects3 = Journal.get_effects(journal, signal3.id)

      refute Enum.empty?(effects1)
      refute Enum.empty?(effects2)
      assert effects3 == []
      assert hd(effects1).id == signal2.id
      assert hd(effects2).id == signal3.id

      # Check causes (backward causality)
      cause3 = Journal.get_cause(journal, signal3.id)
      cause2 = Journal.get_cause(journal, signal2.id)
      cause1 = Journal.get_cause(journal, signal1.id)

      assert cause3.id == signal2.id
      assert cause2.id == signal1.id
      assert cause1 == nil
    end

    test "validates causality - non-existent cause" do
      journal = Journal.new()
      signal = Signal.new!(type: "test.event", source: "/test")

      assert {:error, :cause_not_found} = Journal.record(journal, signal, "non-existent")
    end

    test "validates causality - no cycles allowed" do
      journal = Journal.new()
      signal1 = Signal.new!(type: "test.event", source: "/test")
      signal2 = Signal.new!(type: "test.event", source: "/test")

      {:ok, journal} = Journal.record(journal, signal1)
      {:ok, journal} = Journal.record(journal, signal2, signal1.id)

      # Try to make signal1 depend on signal2, creating a cycle
      signal3 = Signal.new!(type: "test.event", source: "/test")
      {:ok, journal} = Journal.record(journal, signal3, signal2.id)
      assert {:error, :causality_cycle} = Journal.record(journal, signal1, signal3.id)
    end

    test "validates causality - temporal order" do
      journal = Journal.new()
      signal1 = Signal.new!(type: "test.event", source: "/test")
      # Ensure different timestamps
      Process.sleep(10)
      signal2 = Signal.new!(type: "test.event", source: "/test")

      {:ok, journal} = Journal.record(journal, signal2)
      assert {:error, :invalid_temporal_order} = Journal.record(journal, signal1, signal2.id)
    end
  end

  describe "get_conversation/2" do
    test "returns empty list for unknown conversation" do
      journal = Journal.new()
      assert Journal.get_conversation(journal, "unknown") == []
    end

    test "returns signals in chronological order" do
      journal = Journal.new()
      signal1 = Signal.new!(type: "test.event", source: "/test", subject: "conv1")
      # Ensure different timestamps
      Process.sleep(10)
      signal2 = Signal.new!(type: "test.event", source: "/test", subject: "conv1")

      {:ok, journal} = Journal.record(journal, signal2)
      {:ok, journal} = Journal.record(journal, signal1)

      [first, second] = Journal.get_conversation(journal, "conv1")
      assert first.id == signal1.id
      assert second.id == signal2.id
    end
  end

  describe "get_effects/2" do
    test "returns empty list for unknown signal" do
      journal = Journal.new()
      assert Journal.get_effects(journal, "unknown") == []
    end

    test "returns empty list for signal with no effects" do
      journal = Journal.new()
      signal = Signal.new!(type: "test.event", source: "/test")
      {:ok, journal} = Journal.record(journal, signal)
      assert Journal.get_effects(journal, signal.id) == []
    end
  end

  describe "get_cause/2" do
    test "returns nil for unknown signal" do
      journal = Journal.new()
      assert Journal.get_cause(journal, "unknown") == nil
    end

    test "returns nil for signal with no cause" do
      journal = Journal.new()
      signal = Signal.new!(type: "test.event", source: "/test")
      {:ok, journal} = Journal.record(journal, signal)
      assert Journal.get_cause(journal, signal.id) == nil
    end
  end

  describe "trace_chain/3" do
    test "traces forward chain of signals" do
      journal = Journal.new()
      signal1 = Signal.new!(type: "test.event", source: "/test")
      signal2 = Signal.new!(type: "test.event", source: "/test")
      signal3 = Signal.new!(type: "test.event", source: "/test")

      {:ok, journal} = Journal.record(journal, signal1)
      {:ok, journal} = Journal.record(journal, signal2, signal1.id)
      {:ok, journal} = Journal.record(journal, signal3, signal2.id)

      chain = Journal.trace_chain(journal, signal1.id, :forward)
      assert length(chain) == 3
      assert Enum.map(chain, & &1.id) == [signal1.id, signal2.id, signal3.id]
    end

    test "traces backward chain of signals" do
      journal = Journal.new()
      signal1 = Signal.new!(type: "test.event", source: "/test")
      signal2 = Signal.new!(type: "test.event", source: "/test")
      signal3 = Signal.new!(type: "test.event", source: "/test")

      {:ok, journal} = Journal.record(journal, signal1)
      {:ok, journal} = Journal.record(journal, signal2, signal1.id)
      {:ok, journal} = Journal.record(journal, signal3, signal2.id)

      chain = Journal.trace_chain(journal, signal3.id, :backward)
      assert length(chain) == 3
      assert Enum.map(chain, & &1.id) == [signal3.id, signal2.id, signal1.id]
    end

    test "handles branching chains" do
      journal = Journal.new()
      signal1 = Signal.new!(type: "test.event", source: "/test")
      signal2a = Signal.new!(type: "test.event", source: "/test")
      signal2b = Signal.new!(type: "test.event", source: "/test")

      {:ok, journal} = Journal.record(journal, signal1)
      {:ok, journal} = Journal.record(journal, signal2a, signal1.id)
      {:ok, journal} = Journal.record(journal, signal2b, signal1.id)

      chain = Journal.trace_chain(journal, signal1.id, :forward)
      assert length(chain) == 3

      assert Enum.map(chain, & &1.id) |> MapSet.new() ==
               MapSet.new([signal1.id, signal2a.id, signal2b.id])
    end
  end

  describe "query/2" do
    @tag :flaky
    test "filters signals by type" do
      journal = Journal.new()
      signal1 = Signal.new!(type: "type1", source: "/test")
      signal2 = Signal.new!(type: "type2", source: "/test")

      {:ok, journal} = Journal.record(journal, signal1)
      {:ok, journal} = Journal.record(journal, signal2)

      results = Journal.query(journal, type: "type1")
      assert length(results) == 1
      assert hd(results).id == signal1.id
    end

    test "filters signals by source" do
      journal = Journal.new()
      signal1 = Signal.new!(type: "test", source: "/source1")
      signal2 = Signal.new!(type: "test", source: "/source2")

      {:ok, journal} = Journal.record(journal, signal1)
      {:ok, journal} = Journal.record(journal, signal2)

      results = Journal.query(journal, source: "/source1")
      assert length(results) == 1
      assert hd(results).id == signal1.id
    end

    test "filters signals by time range" do
      journal = Journal.new()
      signal1 = Signal.new!(type: "test", source: "/test")
      Process.sleep(10)
      middle_time = DateTime.utc_now()
      Process.sleep(10)
      signal2 = Signal.new!(type: "test", source: "/test")

      {:ok, journal} = Journal.record(journal, signal1)
      {:ok, journal} = Journal.record(journal, signal2)

      results = Journal.query(journal, after: middle_time)
      assert length(results) == 1
      assert hd(results).id == signal2.id
    end

    test "combines multiple filters" do
      journal = Journal.new()
      signal1 = Signal.new!(type: "type1", source: "/source1")
      signal2 = Signal.new!(type: "type1", source: "/source2")
      signal3 = Signal.new!(type: "type2", source: "/source1")

      {:ok, journal} = Journal.record(journal, signal1)
      {:ok, journal} = Journal.record(journal, signal2)
      {:ok, journal} = Journal.record(journal, signal3)

      results = Journal.query(journal, type: "type1", source: "/source1")
      assert length(results) == 1
      assert hd(results).id == signal1.id
    end
  end
end
