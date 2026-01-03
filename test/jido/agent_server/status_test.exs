defmodule JidoTest.AgentServer.StatusTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer
  alias Jido.AgentServer.Status
  alias Jido.Signal
  alias JidoTest.WaitHelpers

  # Test actions
  defmodule IncrementAction do
    @moduledoc false
    use Jido.Action, name: "test_increment", schema: []

    def run(_params, context) do
      count = Map.get(context.state, :counter, 0)
      {:ok, %{counter: count + 1}}
    end
  end

  defmodule CompleteAction do
    @moduledoc false
    use Jido.Action, name: "test_complete", schema: []

    def run(_params, context) do
      {:ok, %{status: :completed, result: context.state.counter}}
    end
  end

  # Simple test agent with Direct strategy
  defmodule TestAgent do
    use Jido.Agent,
      name: "test_agent",
      strategy: Jido.Agent.Strategy.Direct,
      schema: [
        counter: [type: :integer, default: 0],
        status: [type: :atom, default: :idle]
      ]

    def signal_routes do
      [
        {"test_increment", IncrementAction},
        {"test.complete", CompleteAction}
      ]
    end
  end

  describe "Status struct" do
    setup %{jido: jido} do
      {:ok, pid} = AgentServer.start(agent: TestAgent, jido: jido)

      on_exit(fn ->
        if Process.alive?(pid) do
          try do
            GenServer.stop(pid)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      {:ok, pid: pid}
    end

    test "status/1 returns Status struct with correct fields", %{pid: pid} do
      {:ok, status} = AgentServer.status(pid)

      assert %Status{} = status
      assert status.agent_module == TestAgent
      assert is_binary(status.agent_id)
      assert status.pid == pid
      assert %Jido.Agent.Strategy.Snapshot{} = status.snapshot
      assert is_map(status.raw_state)
    end

    test "status includes snapshot from strategy", %{pid: pid} do
      {:ok, status} = AgentServer.status(pid)

      assert status.snapshot.status in [:idle, :running, :waiting, :success, :failure]
      assert is_boolean(status.snapshot.done?)
      assert is_map(status.snapshot.details)
    end

    test "status includes raw_state as escape hatch", %{pid: pid} do
      {:ok, status} = AgentServer.status(pid)

      assert status.raw_state.counter == 0
      assert status.raw_state.status == :idle
    end

    test "delegate helper functions work", %{pid: pid} do
      {:ok, status} = AgentServer.status(pid)

      assert Status.status(status) in [:idle, :running, :waiting, :success, :failure]
      assert is_boolean(Status.done?(status))
      assert is_map(Status.details(status))
    end
  end

  describe "AgentServer.status/1" do
    setup %{jido: jido} do
      {:ok, pid} = AgentServer.start(agent: TestAgent, jido: jido)

      on_exit(fn ->
        if Process.alive?(pid) do
          try do
            GenServer.stop(pid)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      {:ok, pid: pid}
    end

    test "returns {:ok, status} for valid agent", %{pid: pid} do
      assert {:ok, %Status{}} = AgentServer.status(pid)
    end

    test "works with PID", %{pid: pid} do
      assert {:ok, status} = AgentServer.status(pid)
      assert status.pid == pid
    end

    test "works with agent ID", %{pid: pid, jido: jido} do
      {:ok, state} = AgentServer.state(pid)
      # Use whereis/2 with the test's jido registry to look up by ID
      found_pid = AgentServer.whereis(Jido.registry_name(jido), state.id)
      assert {:ok, status} = AgentServer.status(found_pid)
      assert status.agent_id == state.id
    end

    test "returns error for invalid server" do
      # Atoms are treated as process names and return :not_found
      assert {:error, :not_found} = AgentServer.status(:not_a_server)
    end

    test "returns error for non-existent agent", %{jido: jido} do
      # Use whereis/2 with the test's jido registry to verify not found
      assert nil == AgentServer.whereis(Jido.registry_name(jido), "non-existent-id")
    end

    test "reflects state changes", %{pid: pid} do
      # Initial state
      {:ok, status1} = AgentServer.status(pid)
      assert status1.raw_state.counter == 0

      # Send increment signal
      signal = Signal.new!("test_increment", %{}, source: "test")
      AgentServer.cast(pid, signal)

      WaitHelpers.wait_until(
        fn ->
          case AgentServer.status(pid) do
            {:ok, status} -> status.raw_state.counter == 1
            _ -> false
          end
        end,
        label: "counter to increment"
      )

      # Check updated state
      {:ok, status2} = AgentServer.status(pid)
      assert status2.raw_state.counter == 1
    end

    test "reflects completion", %{pid: pid} do
      # Complete the agent
      signal = Signal.new!("test.complete", %{}, source: "test")
      AgentServer.cast(pid, signal)

      WaitHelpers.wait_until(
        fn ->
          case AgentServer.status(pid) do
            {:ok, status} -> status.raw_state.status == :completed
            _ -> false
          end
        end,
        label: "agent to complete"
      )

      {:ok, status} = AgentServer.status(pid)
      assert status.raw_state.status == :completed
    end
  end

  describe "AgentServer.stream_status/2" do
    setup %{jido: jido} do
      {:ok, pid} = AgentServer.start(agent: TestAgent, jido: jido)

      on_exit(fn ->
        if Process.alive?(pid) do
          try do
            GenServer.stop(pid)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      {:ok, pid: pid}
    end

    test "returns a stream of status snapshots", %{pid: pid} do
      stream = AgentServer.stream_status(pid, interval_ms: 10)

      statuses = stream |> Enum.take(3)

      assert length(statuses) == 3
      assert Enum.all?(statuses, &match?(%Status{}, &1))
    end

    test "can monitor state changes via stream", %{pid: pid} do
      parent = self()

      # Start streaming in a task
      task =
        Task.async(fn ->
          try do
            AgentServer.stream_status(pid, interval_ms: 20)
            |> Stream.transform(false, fn status, started? ->
              if not started?, do: send(parent, :stream_started)
              {[status], true}
            end)
            |> Enum.reduce_while([], fn status, acc ->
              new_acc = [status.raw_state[:counter] | acc]

              if status.raw_state[:counter] >= 3 do
                {:halt, Enum.reverse(new_acc)}
              else
                {:cont, new_acc}
              end
            end)
          catch
            :exit, _ -> []
          end
        end)

      assert_receive :stream_started, 1000

      for _i <- 1..3 do
        signal = Signal.new!("test_increment", %{}, source: "test")
        AgentServer.cast(pid, signal)
      end

      # Check we saw the progression
      counters = Task.await(task, 2000)
      assert 3 in counters
    end

    test "stream respects interval_ms option", %{pid: pid} do
      start_time = System.monotonic_time(:millisecond)

      AgentServer.stream_status(pid, interval_ms: 100)
      |> Enum.take(3)

      elapsed = System.monotonic_time(:millisecond) - start_time

      # Should take at least 200ms for 3 items with 100ms interval (between items)
      assert elapsed >= 200
    end

    test "stream can detect completion", %{pid: pid} do
      parent = self()

      task =
        Task.async(fn ->
          AgentServer.stream_status(pid, interval_ms: 20)
          |> Stream.transform(false, fn status, started? ->
            if not started?, do: send(parent, :stream_started)
            {[status], true}
          end)
          |> Enum.reduce_while(nil, fn status, _acc ->
            if status.raw_state[:status] == :completed do
              {:halt, {:completed, status.raw_state[:result]}}
            else
              {:cont, nil}
            end
          end)
        end)

      assert_receive :stream_started, 1000

      # Send completion signal
      signal = Signal.new!("test.complete", %{}, source: "test")
      AgentServer.cast(pid, signal)

      result = Task.await(task, 2000)
      assert match?({:completed, _}, result)
    end
  end

  describe "Debug events" do
    setup do
      # Save original config
      original = Application.get_env(:jido, :observability, [])

      on_exit(fn ->
        Application.put_env(:jido, :observability, original)
      end)

      {:ok, original: original}
    end

    test "emit_debug_event/3 emits when debug_events is :all" do
      Application.put_env(:jido, :observability, debug_events: :all)

      # Attach handler to capture event
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-debug-handler",
        [:test, :debug, :event],
        fn event, measurements, metadata, _config ->
          send(test_pid, {ref, event, measurements, metadata})
        end,
        nil
      )

      Jido.Observe.emit_debug_event(
        [:test, :debug, :event],
        %{count: 1},
        %{test: true}
      )

      assert_receive {^ref, [:test, :debug, :event], %{count: 1}, %{test: true}}, 100

      :telemetry.detach("test-debug-handler")
    end

    test "emit_debug_event/3 does not emit when debug_events is :off" do
      Application.put_env(:jido, :observability, debug_events: :off)

      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-debug-handler-off",
        [:test, :debug, :event],
        fn event, measurements, metadata, _config ->
          send(test_pid, {ref, event, measurements, metadata})
        end,
        nil
      )

      Jido.Observe.emit_debug_event(
        [:test, :debug, :event],
        %{count: 1},
        %{test: true}
      )

      refute_receive {^ref, _, _, _}, 100

      :telemetry.detach("test-debug-handler-off")
    end

    test "debug_enabled?/0 returns true when configured" do
      Application.put_env(:jido, :observability, debug_events: :all)
      assert Jido.Observe.debug_enabled?() == true

      Application.put_env(:jido, :observability, debug_events: :minimal)
      assert Jido.Observe.debug_enabled?() == true
    end

    test "debug_enabled?/0 returns false when disabled" do
      Application.put_env(:jido, :observability, debug_events: :off)
      assert Jido.Observe.debug_enabled?() == false

      Application.put_env(:jido, :observability, [])
      assert Jido.Observe.debug_enabled?() == false
    end
  end

  describe "Redaction" do
    setup do
      original = Application.get_env(:jido, :observability, [])

      on_exit(fn ->
        Application.put_env(:jido, :observability, original)
      end)

      {:ok, original: original}
    end

    test "redact/1 redacts when redact_sensitive is true" do
      Application.put_env(:jido, :observability, redact_sensitive: true)

      assert Jido.Observe.redact("sensitive data") == "[REDACTED]"
      assert Jido.Observe.redact(%{key: "value"}) == "[REDACTED]"
    end

    test "redact/1 does not redact when redact_sensitive is false" do
      Application.put_env(:jido, :observability, redact_sensitive: false)

      assert Jido.Observe.redact("sensitive data") == "sensitive data"
      assert Jido.Observe.redact(%{key: "value"}) == %{key: "value"}
    end

    test "redact/2 respects force_redact option" do
      Application.put_env(:jido, :observability, redact_sensitive: false)

      assert Jido.Observe.redact("data", force_redact: true) == "[REDACTED]"
    end

    test "redact/1 defaults to not redacting" do
      Application.put_env(:jido, :observability, [])

      assert Jido.Observe.redact("data") == "data"
    end
  end
end
