defmodule Jido.Agent.Server.OutputTest do
  use JidoTest.Case, async: true
  require Logger
  import ExUnit.CaptureLog

  alias JidoTest.TestAgents.BasicAgent
  alias Jido.Agent.Server
  alias Jido.Agent.Server.Output
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Signal
  alias Jido.Signal.DispatchHelpers
  alias JidoTest.TestAgents.SignalOutputAgent

  @receive_timeout 500

  setup do
    # Register test process for assertions
    test_pid = self()
    Process.put(:test_pid, test_pid)

    on_exit(fn ->
      Process.delete(:test_pid)
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
      # Set to debug to allow all levels
      log_level: :debug
    }

    {:ok, %{state: state, test_pid: test_pid}}
  end

  describe "log/4" do
    test "logs message with state log level and agent id", %{state: state} do
      log =
        capture_log([level: :info], fn ->
          Output.log(state, :info, "Test message", [])
        end)

      assert log =~ "[info]"
      assert log =~ "Test message"
    end

    test "logs message with explicit log level", %{state: state} do
      log =
        capture_log([level: :warning], fn ->
          Output.log(state, :warning, "Warning message", [])
        end)

      assert log =~ "[warning]"
      assert log =~ "Warning message"
    end

    test "handles all log levels", %{state: state} do
      levels = [:debug, :info, :notice, :warning, :error, :critical, :alert, :emergency]

      Enum.each(levels, fn level ->
        log =
          capture_log([level: level], fn ->
            Output.log(state, level, "#{level} message", [])
            # Give logger time to process
            Process.sleep(10)
          end)

        assert log =~ "[#{level}]"
        assert log =~ "#{level} message"
      end)
    end

    test "includes custom metadata in log", %{state: state} do
      log =
        capture_log([level: :info], fn ->
          Output.log(state, :info, "Test with metadata", custom_field: "test")
        end)

      assert log =~ "[info]"
      assert log =~ "Test with metadata"
    end

    test "doesn't affect global log level", %{state: state} do
      # Get global log level before test
      original_level = Logger.level()

      # Log at warning level
      capture_log([level: :warning], fn ->
        Output.log(state, :warning, "Test message", [])
      end)

      # Verify global level hasn't changed
      assert Logger.level() == original_level
    end
  end

  describe "emit/2" do
    test "emits signal with default channel", %{state: state} do
      {:ok, signal} = Signal.new(%{type: "test.signal", data: "test", id: "test-id-123"})

      log =
        capture_log([level: :info], fn ->
          assert :ok = Output.emit(signal, state)
          Process.sleep(50)
        end)

      # Verify log contains all important signal information
      assert log =~ "SIGNAL: test.signal"
      assert log =~ "test"
      assert log =~ "Elixir.Jido.Agent.Server.OutputTest"
    end

    test "handles signal with dispatch extension config", %{state: state} do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          data: "test",
          id: "test-id-456"
        })

      {:ok, signal} =
        DispatchHelpers.put_dispatch(signal, {:pid, [target: self(), delivery_mode: :async]})

      capture_log([level: :info], fn ->
        assert :ok = Output.emit(signal, state)

        assert_receive {:signal, %Signal{type: "test.signal", data: "test", id: "test-id-456"}},
                       @receive_timeout
      end)
    end

    test "handles signal with multiple dispatch extension configs", %{state: state} do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          data: "test",
          id: "test-id-789"
        })

      {:ok, signal} =
        DispatchHelpers.put_dispatch(signal, [
          {:pid, [target: self(), delivery_mode: :async]},
          {:pid, [target: self(), delivery_mode: :async, test: true]}
        ])

      capture_log([level: :info], fn ->
        assert :ok = Output.emit(signal, state)

        assert_receive {:signal, %Signal{type: "test.signal", data: "test", id: "test-id-789"}},
                       @receive_timeout

        assert_receive {:signal, %Signal{type: "test.signal", data: "test", id: "test-id-789"}},
                       @receive_timeout
      end)
    end

    test "handles signal with dispatch config in opts", %{state: state} do
      {:ok, signal} = Signal.new(%{type: "test.signal", data: "test", id: "test-id-101112"})

      capture_log([level: :info], fn ->
        assert :ok =
                 Output.emit(signal, state,
                   dispatch: {:pid, [target: self(), delivery_mode: :async]}
                 )

        assert_receive {:signal,
                        %Signal{type: "test.signal", data: "test", id: "test-id-101112"}},
                       @receive_timeout
      end)
    end

    test "handles list of dispatch configs", %{state: state} do
      {:ok, signal} = Signal.new(%{type: "test.signal", data: "test"})

      log =
        capture_log([level: :info], fn ->
          assert :ok =
                   Output.emit(signal, state,
                     dispatch: [
                       {Jido.Signal.Dispatch.LoggerAdapter, []},
                       {:pid, [target: self(), delivery_mode: :async]}
                     ]
                   )

          assert_receive {:signal, %Signal{type: "test.signal", data: "test"}},
                         @receive_timeout

          Process.sleep(50)
        end)

      assert log =~ "SIGNAL: test.signal"
      assert log =~ "data=\"test\""
    end
  end

  describe "log level integration" do
    test "respects server log level configuration" do
      # Create a new agent instance with a unique ID
      {:ok, pid} = Server.start_link(agent: BasicAgent, log_level: :debug)
      {:ok, state} = Server.state(pid)

      # Capture all logs and check their levels
      log =
        capture_log([level: :debug], fn ->
          Output.log(state, :debug, "Debug message", [])
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
        capture_log([level: :debug], fn ->
          # Debug message should not be logged at error level
          Output.log(state2, :debug, "Debug message", [])
          # Error message should be logged at error level
          Output.log(state2, :error, "Error message", [])
          Process.sleep(10)
        end)

      # Only error message should be logged since that's the server's log level
      refute error_log =~ "Debug message"
      assert error_log =~ "[error]"
      assert error_log =~ "Error message"
    end

    test "includes agent id in log metadata" do
      id = "test-agent-#{System.unique_integer([:positive])}"
      agent = BasicAgent.new(id)
      {:ok, pid} = Server.start_link(agent: agent, log_level: :info)
      {:ok, state} = Server.state(pid)

      log =
        capture_log([level: :info], fn ->
          Output.log(state, :info, "Test message", [])
          Process.sleep(10)
        end)

      assert log =~ "[info]"
      assert log =~ "Test message"
    end
  end
end
