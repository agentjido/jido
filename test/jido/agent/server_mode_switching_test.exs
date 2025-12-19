defmodule Jido.Agent.ServerModeSwitchingTest do
  use JidoTest.Case, async: true

  alias Jido.Agent.Server
  alias Jido.Signal
  alias JidoTest.TestAgents.BasicAgent

  @moduletag :phase2
  @moduletag :capture_log

  setup do
    # Start a unique test registry for each test
    registry_name = :"TestRegistry_#{System.unique_integer([:positive, :monotonic])}"
    {:ok, _} = Registry.start_link(keys: :unique, name: registry_name)

    %{registry: registry_name}
  end

  describe "runtime mode switching via GenServer call" do
    test "can switch from :auto to :step mode", %{registry: registry} do
      {:ok, pid} = Server.start_link(agent: BasicAgent, mode: :auto, registry: registry)

      # Verify initial mode
      {:ok, initial_state} = Server.state(pid)
      assert initial_state.mode == :auto

      # Switch to :step mode
      result = GenServer.call(pid, {:set_mode, :step})
      assert result == {:ok, :step}

      # Verify mode changed
      {:ok, updated_state} = Server.state(pid)
      assert updated_state.mode == :step
    end

    test "can switch from :step to :debug mode", %{registry: registry} do
      {:ok, pid} = Server.start_link(agent: BasicAgent, mode: :step, registry: registry)

      # Verify initial mode
      {:ok, initial_state} = Server.state(pid)
      assert initial_state.mode == :step

      # Switch to :debug mode
      result = GenServer.call(pid, {:set_mode, :debug})
      assert result == {:ok, :debug}

      # Verify mode changed
      {:ok, updated_state} = Server.state(pid)
      assert updated_state.mode == :debug
    end

    test "can switch from :debug to :auto mode", %{registry: registry} do
      {:ok, pid} = Server.start_link(agent: BasicAgent, mode: :debug, registry: registry)

      # Verify initial mode
      {:ok, initial_state} = Server.state(pid)
      assert initial_state.mode == :debug

      # Switch to :auto mode
      result = GenServer.call(pid, {:set_mode, :auto})
      assert result == {:ok, :auto}

      # Verify mode changed
      {:ok, updated_state} = Server.state(pid)
      assert updated_state.mode == :auto
    end

    test "returns error for invalid mode", %{registry: registry} do
      {:ok, pid} = Server.start_link(agent: BasicAgent, mode: :auto, registry: registry)

      # Try to set invalid mode
      result = GenServer.call(pid, {:set_mode, :invalid})
      assert result == {:error, :unsupported_mode}

      # Verify mode unchanged
      {:ok, state} = Server.state(pid)
      assert state.mode == :auto
    end

    test "returns error for non-atom mode", %{registry: registry} do
      {:ok, pid} = Server.start_link(agent: BasicAgent, mode: :auto, registry: registry)

      # Try to set non-atom mode
      result = GenServer.call(pid, {:set_mode, "step"})
      assert result == {:error, :unsupported_mode}

      # Verify mode unchanged
      {:ok, state} = Server.state(pid)
      assert state.mode == :auto
    end

    test "setting same mode returns success", %{registry: registry} do
      {:ok, pid} = Server.start_link(agent: BasicAgent, mode: :step, registry: registry)

      # Set to same mode
      result = GenServer.call(pid, {:set_mode, :step})
      assert result == {:ok, :step}

      # Verify mode unchanged
      {:ok, state} = Server.state(pid)
      assert state.mode == :step
    end
  end

  describe "mode switching with telemetry/events" do
    test "emits mode_changed event when mode changes", %{registry: registry} do
      {:ok, pid} = Server.start_link(agent: BasicAgent, mode: :auto, registry: registry)

      # Capture telemetry events
      test_pid = self()
      handler_id = :test_mode_change_handler

      :telemetry.attach(
        handler_id,
        [:jido, :dispatch, :stop],
        fn event_name, measurements, metadata, _config ->
          if metadata.signal_type == "jido.agent.event.mode.changed" do
            send(test_pid, {:telemetry_event, event_name, measurements, metadata})
          end
        end,
        nil
      )

      # Switch mode
      GenServer.call(pid, {:set_mode, :step})

      # Verify telemetry event was emitted
      assert_receive {:telemetry_event, [:jido, :dispatch, :stop], _measurements, metadata}
      assert metadata.signal_type == "jido.agent.event.mode.changed"
      # The from/to data would be in the signal's data, not in the dispatch metadata

      :telemetry.detach(handler_id)
    end

    test "does not emit event when setting same mode", %{registry: registry} do
      {:ok, pid} = Server.start_link(agent: BasicAgent, mode: :step, registry: registry)

      # Capture telemetry events
      test_pid = self()
      handler_id = :test_same_mode_handler

      :telemetry.attach(
        handler_id,
        [:jido, :dispatch, :stop],
        fn event_name, measurements, metadata, _config ->
          if metadata.signal_type == "jido.agent.event.mode.changed" do
            send(test_pid, {:telemetry_event, event_name, measurements, metadata})
          end
        end,
        nil
      )

      # Set same mode
      GenServer.call(pid, {:set_mode, :step})

      # Verify no telemetry event was emitted
      refute_receive {:telemetry_event, [:jido, :dispatch, :stop], _, _}, 100

      :telemetry.detach(handler_id)
    end
  end

  describe "runtime behavior with switched modes" do
    test "signals are processed automatically after switching to :auto", %{registry: registry} do
      {:ok, pid} = Server.start_link(agent: BasicAgent, mode: :step, registry: registry)

      # Send a signal in :step mode - should be queued
      signal = Signal.new!(%{type: "test", data: %{}})
      Server.cast(pid, signal)

      # Verify signal is queued
      {:ok, state} = Server.state(pid)
      assert :queue.len(state.pending_signals) == 1

      # Switch to :auto mode
      GenServer.call(pid, {:set_mode, :auto})

      # Give time for queue processing
      Process.sleep(10)

      # Verify queue was processed
      {:ok, final_state} = Server.state(pid)
      assert :queue.len(final_state.pending_signals) == 0
    end

    test "signals are queued after switching to :step", %{registry: registry} do
      {:ok, pid} = Server.start_link(agent: BasicAgent, mode: :auto, registry: registry)

      # Switch to :step mode
      GenServer.call(pid, {:set_mode, :step})

      # Send a signal - should be queued
      signal = Signal.new!(%{type: "test", data: %{}})
      Server.cast(pid, signal)

      # Verify signal is queued
      {:ok, state} = Server.state(pid)
      assert :queue.len(state.pending_signals) == 1
    end

    test "signals are queued after switching to :debug", %{registry: registry} do
      {:ok, pid} = Server.start_link(agent: BasicAgent, mode: :auto, registry: registry)

      # Switch to :debug mode
      GenServer.call(pid, {:set_mode, :debug})

      # Send a signal - should be queued
      signal = Signal.new!(%{type: "test", data: %{}})
      Server.cast(pid, signal)

      # Verify signal is queued (debug mode behaves like step mode for queue processing)
      {:ok, state} = Server.state(pid)
      assert :queue.len(state.pending_signals) == 1
    end
  end

  describe "multiple rapid mode switches" do
    test "handles rapid mode switches correctly", %{registry: registry} do
      {:ok, pid} = Server.start_link(agent: BasicAgent, mode: :auto, registry: registry)

      # Rapid mode switches
      assert {:ok, :step} = GenServer.call(pid, {:set_mode, :step})
      assert {:ok, :debug} = GenServer.call(pid, {:set_mode, :debug})
      assert {:ok, :auto} = GenServer.call(pid, {:set_mode, :auto})
      assert {:ok, :step} = GenServer.call(pid, {:set_mode, :step})

      # Verify final mode
      {:ok, state} = Server.state(pid)
      assert state.mode == :step
    end

    test "preserves agent state through mode switches", %{registry: registry} do
      {:ok, pid} = Server.start_link(agent: BasicAgent, mode: :auto, registry: registry)

      # Get initial agent state
      {:ok, initial_state} = Server.state(pid)
      initial_agent_id = initial_state.agent.id

      # Multiple mode switches
      GenServer.call(pid, {:set_mode, :step})
      GenServer.call(pid, {:set_mode, :debug})
      GenServer.call(pid, {:set_mode, :auto})

      # Verify agent state preserved
      {:ok, final_state} = Server.state(pid)
      assert final_state.agent.id == initial_agent_id
      assert final_state.mode == :auto
    end
  end
end
