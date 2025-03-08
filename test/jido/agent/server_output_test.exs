defmodule Jido.Agent.Server.OutputTest do
  use JidoTest.Case, async: true
  require Logger
  import ExUnit.CaptureLog

  alias JidoTest.TestAgents.BasicAgent
  alias Jido.Agent.Server
  alias Jido.Agent.Server.Output
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Signal
  alias JidoTest.TestAgents.SignalOutputAgent

  @receive_timeout 500

  setup do
    # Save original log level and set to :info for test isolation
    original_level = Logger.level()
    :ok = Logger.configure(level: :info)

    # Register test process for assertions
    test_pid = self()
    Process.put(:test_pid, test_pid)

    on_exit(fn ->
      Process.delete(:test_pid)
      # Restore original log level
      Logger.configure(level: original_level)
    end)

    agent = SignalOutputAgent.new("test-agent-123")

    state = %ServerState{
      agent: agent,
      dispatch: [
        {:logger, []},
        {:pid, [target: self(), delivery_mode: :async]}
      ],
      router: Jido.Signal.Router.new(),
      skills: [],
      status: :idle,
      pending_signals: [],
      max_queue_size: 10_000,
      log_level: :info
    }

    {:ok, %{state: state, test_pid: test_pid, original_log_level: original_level}}
  end

  describe "log/3" do
    test "logs message with state log level and agent id", %{state: state} do
      log =
        capture_log([level: :info], fn ->
          Output.log(state, "Test message")
        end)

      assert log =~ "Test message"
      assert log =~ "agent_id=test-agent-123"
    end

    test "logs message with explicit log level" do
      log =
        capture_log([level: :warning], fn ->
          Output.log(:warning, "Warning message")
        end)

      assert log =~ "Warning message"
    end

    test "handles all log levels" do
      levels = [:debug, :info, :notice, :warning, :error, :critical, :alert, :emergency]

      Enum.each(levels, fn level ->
        log =
          capture_log([level: level], fn ->
            Output.log(level, "#{level} message")
          end)

        assert log =~ "#{level} message"
      end)
    end

    test "includes custom metadata in log", %{state: state} do
      log =
        capture_log([level: :info], fn ->
          Output.log(state, "Test with metadata", metadata: "test")
        end)

      assert log =~ "Test with metadata"
      assert log =~ "metadata=test"
      assert log =~ "agent_id=test-agent-123"
    end

    @tag :flaky
    test "restores original log level after logging", %{original_log_level: original_level} do
      # Ensure we start with original level
      Logger.configure(level: original_level)

      # Log at a different level
      capture_log([level: :warning], fn ->
        Output.log(:warning, "Test message")
      end)

      # Give the logger more time to restore the level
      Process.sleep(100)
      assert Logger.level() == original_level
    end
  end

  describe "emit/2" do
    @tag :flaky
    test "emits signal with default channel" do
      {:ok, signal} = Signal.new(%{type: "test.signal", data: "test", id: "test-id-123"})

      log =
        capture_log([level: :info], fn ->
          assert :ok = Output.emit(signal)
          Process.sleep(50)
        end)

      # Verify log contains all important signal information
      assert log =~ "Signal dispatched"
      assert log =~ "test.signal"
      assert log =~ "test"
      assert log =~ "Elixir.Jido.Agent.Server.OutputTest"
    end

    test "handles signal with jido_dispatch dispatch config" do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          data: "test",
          id: "test-id-456",
          jido_dispatch: {:pid, [target: self(), delivery_mode: :async]}
        })

      capture_log([level: :info], fn ->
        assert :ok = Output.emit(signal)

        assert_receive {:signal, %Signal{type: "test.signal", data: "test", id: "test-id-456"}},
                       @receive_timeout
      end)
    end

    test "handles signal with multiple jido_dispatch dispatch configs" do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          data: "test",
          id: "test-id-789",
          jido_dispatch: [
            {:pid, [target: self(), delivery_mode: :async]},
            {:pid, [target: self(), delivery_mode: :async, test: true]}
          ]
        })

      capture_log([level: :info], fn ->
        assert :ok = Output.emit(signal)

        assert_receive {:signal, %Signal{type: "test.signal", data: "test", id: "test-id-789"}},
                       @receive_timeout

        assert_receive {:signal, %Signal{type: "test.signal", data: "test", id: "test-id-789"}},
                       @receive_timeout
      end)
    end

    test "handles signal with dispatch config in opts" do
      {:ok, signal} = Signal.new(%{type: "test.signal", data: "test", id: "test-id-101112"})

      capture_log([level: :info], fn ->
        assert :ok =
                 Output.emit(signal,
                   dispatch: {:pid, [target: self(), delivery_mode: :async]}
                 )

        assert_receive {:signal,
                        %Signal{type: "test.signal", data: "test", id: "test-id-101112"}},
                       @receive_timeout
      end)
    end

    test "handles list of dispatch configs" do
      {:ok, signal} = Signal.new(%{type: "test.signal", data: "test"})

      log =
        capture_log([level: :info], fn ->
          assert :ok =
                   Output.emit(signal,
                     dispatch: [
                       {Jido.Signal.Dispatch.LoggerAdapter, []},
                       {:pid, [target: self(), delivery_mode: :async]}
                     ]
                   )

          assert_receive {:signal, %Signal{type: "test.signal", data: "test"}},
                         @receive_timeout

          Process.sleep(50)
        end)

      assert log =~ "Signal dispatched"
      assert log =~ "test.signal"
    end
  end

  describe "log level integration" do
    test "respects server log level configuration" do
      # Create a new agent instance with a unique ID
      # id = "test-agent-#{System.unique_integer([:positive])}"
      # agent = BasicAgent.new(id)

      # Start server with debug log level
      # {:ok, pid} = Server.start_link(agent: agent, log_level: :debug)
      {:ok, pid} = Server.start_link(agent: BasicAgent, log_level: :debug)
      {:ok, state} = Server.state(pid)

      # Capture all logs and check their levels
      log =
        capture_log(fn ->
          Output.log(state, "Debug message")
          Process.sleep(10)
        end)

      assert log =~ "[debug]"
      assert log =~ "Debug message"

      # Start server with error log level
      agent2 = BasicAgent.new("test-agent-#{System.unique_integer([:positive])}")
      {:ok, pid2} = Server.start_link(agent: agent2, log_level: :error)
      {:ok, state2} = Server.state(pid2)

      # Capture all logs and check their levels
      error_log =
        capture_log(fn ->
          # Debug message should be logged at error level
          Output.log(state2, "Debug message")
          # Error message should be logged at error level
          Output.log(state2, "Error message")
          Process.sleep(10)
        end)

      # Both messages should be at error level since that's the server's log level
      assert error_log =~ "[error] Debug message"
      assert error_log =~ "[error] Error message"
    end

    test "includes agent id in log metadata" do
      id = "test-agent-#{System.unique_integer([:positive])}"
      agent = BasicAgent.new(id)
      {:ok, pid} = Server.start_link(agent: agent, log_level: :info)
      {:ok, state} = Server.state(pid)

      log =
        capture_log([level: :info], fn ->
          Output.log(state, "Test message")
          Process.sleep(10)
        end)

      assert log =~ "Test message"
      assert log =~ "agent_id=#{id}"
    end
  end
end
