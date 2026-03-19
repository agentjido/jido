defmodule JidoTest.AgentServer.SignalTest do
  use ExUnit.Case, async: true

  alias Jido.AgentServer.Signal.{ChildExit, Orphaned, Scheduled}

  describe "Orphaned signal" do
    test "creates signal with correct type" do
      {:ok, signal} =
        Orphaned.new(%{
          parent_id: "parent-123",
          parent_pid: self(),
          tag: :worker,
          meta: %{role: "worker"},
          reason: :normal
        })

      assert signal.type == "jido.agent.orphaned"
      assert signal.data.parent_id == "parent-123"
      assert signal.data.parent_pid == self()
      assert signal.data.tag == :worker
      assert signal.data.meta == %{role: "worker"}
      assert signal.data.reason == :normal
    end

    test "creates signal with custom source" do
      {:ok, signal} =
        Orphaned.new(
          %{
            parent_id: "parent-123",
            parent_pid: self(),
            tag: :worker,
            meta: %{},
            reason: {:shutdown, :timeout}
          },
          source: "/agent/child-456"
        )

      assert signal.source == "/agent/child-456"
      assert signal.data.reason == {:shutdown, :timeout}
    end

    test "new! raises on missing required fields" do
      assert_raise RuntimeError, fn ->
        Orphaned.new!(%{parent_id: "parent-123", parent_pid: self(), tag: :worker, meta: %{}})
      end
    end

    test "validates parent_id is required" do
      {:error, _reason} =
        Orphaned.new(%{parent_pid: self(), tag: :worker, meta: %{}, reason: :normal})
    end
  end

  describe "ChildExit signal" do
    test "creates signal with correct type" do
      pid = self()
      {:ok, signal} = ChildExit.new(%{tag: :worker_1, pid: pid, reason: :normal})

      assert signal.type == "jido.agent.child.exit"
      assert signal.data.tag == :worker_1
      assert signal.data.pid == pid
      assert signal.data.reason == :normal
    end

    test "creates signal with custom source" do
      pid = self()

      {:ok, signal} =
        ChildExit.new(
          %{tag: "my-worker", pid: pid, reason: {:error, :timeout}},
          source: "/agent/parent-123"
        )

      assert signal.source == "/agent/parent-123"
      assert signal.data.tag == "my-worker"
    end

    test "accepts any tag type" do
      pid = self()

      {:ok, signal1} = ChildExit.new(%{tag: :atom_tag, pid: pid, reason: :normal})
      assert signal1.data.tag == :atom_tag

      {:ok, signal2} = ChildExit.new(%{tag: "string_tag", pid: pid, reason: :normal})
      assert signal2.data.tag == "string_tag"

      {:ok, signal3} = ChildExit.new(%{tag: {:tuple, 1}, pid: pid, reason: :normal})
      assert signal3.data.tag == {:tuple, 1}
    end

    test "validates all required fields" do
      {:error, _} = ChildExit.new(%{tag: :worker})
      {:error, _} = ChildExit.new(%{pid: self()})
      {:error, _} = ChildExit.new(%{reason: :normal})
    end
  end

  describe "Scheduled signal" do
    test "creates signal with correct type" do
      {:ok, signal} = Scheduled.new(%{message: :tick})

      assert signal.type == "jido.scheduled"
      assert signal.data.message == :tick
    end

    test "creates signal with custom source" do
      {:ok, signal} =
        Scheduled.new(
          %{message: {:custom, :payload}},
          source: "/agent/scheduler-123"
        )

      assert signal.source == "/agent/scheduler-123"
      assert signal.data.message == {:custom, :payload}
    end

    test "accepts any message type" do
      {:ok, signal1} = Scheduled.new(%{message: :atom_message})
      assert signal1.data.message == :atom_message

      {:ok, signal2} = Scheduled.new(%{message: "string message"})
      assert signal2.data.message == "string message"

      {:ok, signal3} = Scheduled.new(%{message: %{complex: "data", count: 42}})
      assert signal3.data.message == %{complex: "data", count: 42}
    end

    test "validates message is required" do
      {:error, _} = Scheduled.new(%{})
    end
  end

  describe "signal compatibility" do
    test "all signals are valid Jido.Signal structs" do
      {:ok, orphaned} =
        Orphaned.new(%{
          parent_id: "p1",
          parent_pid: self(),
          tag: :worker,
          meta: %{},
          reason: :normal
        })

      {:ok, child_exit} = ChildExit.new(%{tag: :t1, pid: self(), reason: :normal})
      {:ok, scheduled} = Scheduled.new(%{message: :msg})

      assert %Jido.Signal{} = orphaned
      assert %Jido.Signal{} = child_exit
      assert %Jido.Signal{} = scheduled
    end

    test "signals have proper specversion" do
      {:ok, signal} =
        Orphaned.new(%{
          parent_id: "p1",
          parent_pid: self(),
          tag: :worker,
          meta: %{},
          reason: :normal
        })

      assert signal.specversion == "1.0.2"
    end

    test "signals have auto-generated ids" do
      {:ok, signal1} = Scheduled.new(%{message: :a})
      {:ok, signal2} = Scheduled.new(%{message: :b})

      assert is_binary(signal1.id)
      assert is_binary(signal2.id)
      assert signal1.id != signal2.id
    end
  end
end
