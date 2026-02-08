defmodule JidoTest.AgentServerTest do
  use JidoTest.Case, async: true

  @moduletag :capture_log

  alias Jido.Agent.Directive
  alias Jido.AgentServer
  alias Jido.AgentServer.State
  alias Jido.Signal
  alias JidoTest.TestActions

  # Test actions with specific directive behavior (not in common_fixtures)
  defmodule EmitTestAction do
    @moduledoc false
    use Jido.Action, name: "emit_test", schema: []

    def run(_params, _context) do
      signal = Signal.new!("test.emitted", %{from: "agent"}, source: "/test")
      {:ok, %{}, [%Directive.Emit{signal: signal}]}
    end
  end

  defmodule ScheduleTestAction do
    @moduledoc false
    use Jido.Action, name: "schedule_test", schema: []

    def run(_params, _context) do
      scheduled_signal = Signal.new!("scheduled.ping", %{}, source: "/test")
      {:ok, %{}, [%Directive.Schedule{delay_ms: 50, message: scheduled_signal}]}
    end
  end

  defmodule StopTestAction do
    @moduledoc false
    use Jido.Action, name: "stop_test", schema: []

    def run(_params, _context) do
      {:ok, %{}, [%Directive.Stop{reason: :normal}]}
    end
  end

  defmodule ErrorTestAction do
    @moduledoc false
    use Jido.Action, name: "error_test", schema: []

    def run(_params, _context) do
      error = Jido.Error.validation_error("Test error", %{field: :test})
      {:ok, %{}, [%Directive.Error{error: error, context: :test}]}
    end
  end

  defmodule TestAgent do
    @moduledoc false
    use Jido.Agent,
      name: "test_agent",
      schema: [
        counter: [type: :integer, default: 0],
        messages: [type: {:list, :any}, default: []]
      ]

    alias JidoTest.TestActions

    def signal_routes(_ctx) do
      [
        {"increment", TestActions.IncrementAction},
        {"decrement", TestActions.DecrementAction},
        {"record", TestActions.RecordAction},
        {"emit_test", EmitTestAction},
        {"schedule_test", ScheduleTestAction},
        {"stop_test", StopTestAction},
        {"error_test", ErrorTestAction},
        {"noop", TestActions.NoSchema}
      ]
    end
  end

  describe "start_link/1" do
    test "starts with agent module", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts with custom id", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, id: "custom-123", jido: jido)
      {:ok, state} = AgentServer.state(pid)
      assert state.id == "custom-123"
      GenServer.stop(pid)
    end

    test "registers in Registry", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, id: "registry-test", jido: jido)
      assert AgentServer.whereis(Jido.registry_name(jido), "registry-test") == pid
      GenServer.stop(pid)
    end

    test "starts with pre-built agent", %{jido: jido} do
      agent = TestAgent.new(id: "prebuilt-456")
      agent = %{agent | state: Map.put(agent.state, :counter, 99)}

      {:ok, pid} = AgentServer.start_link(agent: agent, agent_module: TestAgent, jido: jido)
      {:ok, state} = AgentServer.state(pid)
      assert state.agent.id == "prebuilt-456"
      assert state.agent.state.counter == 99
      GenServer.stop(pid)
    end

    test "starts with initial_state", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(agent: TestAgent, initial_state: %{counter: 42}, jido: jido)

      {:ok, state} = AgentServer.state(pid)
      assert state.agent.state.counter == 42
      GenServer.stop(pid)
    end
  end

  describe "start/1" do
    test "starts under DynamicSupervisor", %{jido: jido} do
      {:ok, pid} = AgentServer.start(agent: TestAgent, id: "dynamic-test", jido: jido)
      assert Process.alive?(pid)
      assert AgentServer.whereis(Jido.registry_name(jido), "dynamic-test") == pid
      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), pid)
    end

    test "returns already_started when id is already registered", %{jido: jido} do
      id = "duplicate-id-#{System.unique_integer([:positive])}"
      {:ok, pid} = AgentServer.start(agent: TestAgent, id: id, jido: jido)

      assert {:error, {:already_started, ^pid}} =
               AgentServer.start(agent: TestAgent, id: id, jido: jido)

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), pid)
    end
  end

  describe "call/3 (sync)" do
    test "processes signal and returns agent", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)

      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, agent} = AgentServer.call(pid, signal)

      assert agent.state.counter == 1
      GenServer.stop(pid)
    end

    test "processes multiple signals in sequence", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)

      for _ <- 1..5 do
        signal = Signal.new!("increment", %{}, source: "/test")
        {:ok, _agent} = AgentServer.call(pid, signal)
      end

      {:ok, state} = AgentServer.state(pid)
      assert state.agent.state.counter == 5
      GenServer.stop(pid)
    end

    test "records data from signal", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)

      signal = Signal.new!("record", %{message: "hello"}, source: "/test")
      {:ok, agent} = AgentServer.call(pid, signal)

      assert agent.state.messages == ["hello"]
      GenServer.stop(pid)
    end

    test "works with agent ID string", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, id: "call-id-test", jido: jido)

      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, agent} = AgentServer.call(pid, signal)

      assert agent.state.counter == 1
      GenServer.stop(pid)
    end
  end

  describe "cast/2 (async)" do
    test "processes signal asynchronously", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)

      signal = Signal.new!("increment", %{}, source: "/test")
      assert :ok = AgentServer.cast(pid, signal)

      eventually_state(pid, fn state -> state.agent.state.counter == 1 end)

      GenServer.stop(pid)
    end

    test "processes multiple signals", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)

      for _ <- 1..5 do
        signal = Signal.new!("increment", %{}, source: "/test")
        AgentServer.cast(pid, signal)
      end

      eventually_state(pid, fn state -> state.agent.state.counter == 5 end)

      GenServer.stop(pid)
    end
  end

  describe "state/1" do
    test "returns full State struct", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, id: "state-test", jido: jido)
      eventually_state(pid, fn state -> state.status == :idle end)
      {:ok, state} = AgentServer.state(pid)

      assert %State{} = state
      assert state.id == "state-test"
      assert state.agent.state.counter == 0
      assert state.status == :idle

      GenServer.stop(pid)
    end

    test "works with agent ID string", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, id: "state-id-test", jido: jido)
      eventually_state(pid, fn state -> state.status == :idle end)
      {:ok, state} = AgentServer.state(pid)

      assert state.id == "state-id-test"
      GenServer.stop(pid)
    end
  end

  describe "whereis/1 and whereis/2" do
    test "whereis/1 returns pid for registered agent using default registry", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, id: "whereis-test-1", jido: jido)
      assert AgentServer.whereis(Jido.registry_name(jido), "whereis-test-1") == pid
      GenServer.stop(pid)
    end

    test "whereis/1 returns nil for unknown agent", %{jido: jido} do
      assert AgentServer.whereis(Jido.registry_name(jido), "nonexistent") == nil
    end

    test "whereis/2 returns pid for registered agent in specific registry", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(agent: TestAgent, id: "whereis-test-2", jido: jido)

      assert AgentServer.whereis(Jido.registry_name(jido), "whereis-test-2") == pid
      GenServer.stop(pid)
    end

    test "whereis/2 returns nil for unknown agent in specific registry", %{jido: jido} do
      assert AgentServer.whereis(Jido.registry_name(jido), "nonexistent-2") == nil
    end
  end

  describe "via_tuple/2" do
    test "creates valid via tuple", %{jido: jido} do
      via = AgentServer.via_tuple("via-test", Jido.registry_name(jido))
      assert via == {:via, Registry, {Jido.registry_name(jido), "via-test"}}
    end

    test "works with custom registry", %{jido: _jido} do
      via = AgentServer.via_tuple("via-test", MyRegistry)
      assert via == {:via, Registry, {MyRegistry, "via-test"}}
    end
  end

  describe "alive?/1" do
    test "returns true for alive process", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)
      assert AgentServer.alive?(pid)
      GenServer.stop(pid)
    end

    test "returns false for dead process", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)
      GenServer.stop(pid)
      refute AgentServer.alive?(pid)
    end

    test "works with agent ID string", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, id: "alive-test", jido: jido)
      assert AgentServer.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "directive execution" do
    @tag :capture_log
    test "Emit directive is processed", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)

      signal = Signal.new!("emit_test", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      # Drain loop completes and returns to idle
      eventually_state(pid, fn state -> state.status == :idle end)

      GenServer.stop(pid)
    end

    test "Error directive is processed", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)

      signal = Signal.new!("error_test", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      # Drain loop completes and returns to idle
      eventually_state(pid, fn state -> state.status == :idle end)

      GenServer.stop(pid)
    end

    test "Schedule directive schedules a delayed signal", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)

      signal = Signal.new!("schedule_test", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      # Wait for scheduled signal to be processed (50ms delay + processing)
      eventually_state(pid, fn state -> state.status == :idle end, timeout: 200)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "Stop directive stops the server", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)
      ref = Process.monitor(pid)

      signal = Signal.new!("stop_test", %{}, source: "/test")
      AgentServer.cast(pid, signal)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end
  end

  describe "unknown signals" do
    test "returns routing error for unknown signal types", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)

      signal = Signal.new!("unknown.signal.type", %{}, source: "/test")
      assert {:error, %Jido.Error.RoutingError{} = error} = AgentServer.call(pid, signal)
      assert error.message == "No route for signal"
      assert error.details.reason == :no_matching_route

      GenServer.stop(pid)
    end
  end

  describe "drain loop" do
    test "processes directives in order", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)

      # Send multiple signals quickly
      for i <- 1..10 do
        signal = Signal.new!("record", %{index: i}, source: "/test")
        AgentServer.cast(pid, signal)
      end

      state =
        eventually_state(pid, fn state ->
          length(state.agent.state.messages) == 10
        end)

      # Verify order is preserved
      indices = Enum.map(state.agent.state.messages, & &1.index)
      assert indices == Enum.to_list(1..10)

      GenServer.stop(pid)
    end

    test "status transitions correctly", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)

      # Initially idle
      eventually_state(pid, fn state -> state.status == :idle end)
      {:ok, state} = AgentServer.state(pid)
      assert state.status == :idle

      GenServer.stop(pid)
    end
  end

  describe "queue overflow" do
    test "returns error when queue is full", %{jido: jido} do
      # Start with very small queue
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, max_queue_size: 2, jido: jido)

      # Get state and manually fill queue
      {:ok, state} = AgentServer.state(pid)

      # Queue is processed fast, so we test via State module directly
      signal = Signal.new!("record", %{}, source: "/test")
      {:ok, s1} = State.enqueue(state, signal, %Directive.Emit{signal: signal})
      {:ok, s2} = State.enqueue(s1, signal, %Directive.Emit{signal: signal})

      assert {:error, :queue_overflow} =
               State.enqueue(s2, signal, %Directive.Emit{signal: signal})

      GenServer.stop(pid)
    end

    test "queue length is reported correctly", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)
      {:ok, state} = AgentServer.state(pid)

      assert State.queue_length(state) == 0
      assert State.queue_empty?(state)

      signal = Signal.new!("test", %{}, source: "/test")
      {:ok, s1} = State.enqueue(state, signal, %Directive.Emit{signal: signal})
      assert State.queue_length(s1) == 1
      refute State.queue_empty?(s1)

      GenServer.stop(pid)
    end
  end

  describe "status transitions" do
    test "starts as initializing then transitions to idle", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)

      # After post_init continue, should be idle
      eventually_state(pid, fn state -> state.status == :idle end)
      {:ok, state} = AgentServer.state(pid)
      assert state.status == :idle

      GenServer.stop(pid)
    end

    test "serializes blocking call handling inside the server process", %{jido: jido} do
      defmodule SlowAction do
        @moduledoc false
        use Jido.Action,
          name: "slow",
          schema: [
            test_pid: [type: :any, required: false],
            unblock_ref: [type: :any, required: false]
          ]

        def run(%{test_pid: test_pid, unblock_ref: unblock_ref}, _context) do
          send(test_pid, {:slow_action_started, unblock_ref, self()})

          receive do
            {:unblock_slow_action, ^unblock_ref} -> :ok
          after
            2_000 -> :ok
          end

          {:ok, %{}}
        end
      end

      defmodule SlowAgent do
        @moduledoc false
        use Jido.Agent,
          name: "slow_agent",
          schema: [value: [type: :integer, default: 0]]

        def signal_routes(_ctx) do
          [{"slow", SlowAction}]
        end
      end

      {:ok, pid} = AgentServer.start_link(agent: SlowAgent, jido: jido)
      unblock_ref = make_ref()

      # Start async processing
      signal = Signal.new!("slow", %{test_pid: self(), unblock_ref: unblock_ref}, source: "/test")
      task = Task.async(fn -> AgentServer.call(pid, signal) end)

      assert_receive {:slow_action_started, ^unblock_ref, action_pid}, 500

      assert Task.yield(task, 0) == nil
      assert {:timeout, _} = catch_exit(GenServer.call(pid, :get_state, 50))

      send(action_pid, {:unblock_slow_action, unblock_ref})
      Task.await(task, 2_000)

      # After processing completes, status should be idle
      eventually_state(pid, fn state -> state.status == :idle end)

      GenServer.stop(pid)
    end

    test "returns to idle after processing completes", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)

      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      # After processing, wait for drain loop
      eventually_state(pid, fn state -> state.status == :idle end)

      GenServer.stop(pid)
    end
  end

  describe "scheduled signals" do
    test "scheduled signal is processed after delay", %{jido: jido} do
      defmodule StartScheduleAction do
        @moduledoc false
        use Jido.Action, name: "start_schedule", schema: []

        def run(_params, _context) do
          scheduled = Signal.new!("scheduled.ping", %{}, source: "/test")
          {:ok, %{}, [%Directive.Schedule{delay_ms: 50, message: scheduled}]}
        end
      end

      defmodule ScheduledPingAction do
        @moduledoc false
        use Jido.Action, name: "scheduled_ping", schema: []

        def run(_params, context) do
          pings = Map.get(context.state, :pings, 0)
          {:ok, %{pings: pings + 1}}
        end
      end

      defmodule ScheduleTrackingAgent do
        @moduledoc false
        use Jido.Agent,
          name: "schedule_tracking_agent",
          schema: [
            pings: [type: :integer, default: 0]
          ]

        def signal_routes(_ctx) do
          [
            {"start_schedule", StartScheduleAction},
            {"scheduled.ping", ScheduledPingAction}
          ]
        end
      end

      {:ok, pid} = AgentServer.start_link(agent: ScheduleTrackingAgent, jido: jido)

      signal = Signal.new!("start_schedule", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      eventually_state(pid, fn state ->
        map_size(Map.get(state, :scheduled_timers, %{})) == 1
      end)

      # Before delay
      {:ok, state1} = AgentServer.state(pid)
      assert state1.agent.state.pings == 0

      # Wait for scheduled signal (50ms delay + processing)
      eventually_state(pid, fn state -> state.agent.state.pings == 1 end, timeout: 200)

      eventually_state(pid, fn state ->
        map_size(Map.get(state, :scheduled_timers, %{})) == 0
      end)

      GenServer.stop(pid)
    end

    test "multiple scheduled signals are processed", %{jido: jido} do
      defmodule ScheduleManyAction do
        @moduledoc false
        use Jido.Action, name: "schedule_many", schema: []

        def run(_params, _context) do
          directives =
            for i <- 1..3 do
              sig = Signal.new!("tick", %{n: i}, source: "/test")
              %Directive.Schedule{delay_ms: i * 20, message: sig}
            end

          {:ok, %{}, directives}
        end
      end

      defmodule TickAction do
        @moduledoc false
        use Jido.Action, name: "tick", schema: []

        def run(params, context) do
          events = Map.get(context.state, :events, [])
          {:ok, %{events: events ++ [params.n]}}
        end
      end

      defmodule MultiScheduleAgent do
        @moduledoc false
        use Jido.Agent,
          name: "multi_schedule_agent",
          schema: [
            events: [type: {:list, :any}, default: []]
          ]

        def signal_routes(_ctx) do
          [
            {"schedule_many", ScheduleManyAction},
            {"tick", TickAction}
          ]
        end
      end

      {:ok, pid} = AgentServer.start_link(agent: MultiScheduleAgent, jido: jido)

      signal = Signal.new!("schedule_many", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      # Wait for all 3 scheduled signals (20ms, 40ms, 60ms delays)
      state =
        eventually_state(pid, fn state -> state.agent.state.events == [1, 2, 3] end, timeout: 200)

      assert state.agent.state.events == [1, 2, 3]

      GenServer.stop(pid)
    end

    test "non-signal message is wrapped in signal", %{jido: jido} do
      defmodule ScheduleAtomAction do
        @moduledoc false
        use Jido.Action, name: "schedule_atom", schema: []

        def run(_params, _context) do
          {:ok, %{}, [%Directive.Schedule{delay_ms: 10, message: :timeout}]}
        end
      end

      defmodule JidoScheduledAction do
        @moduledoc false
        use Jido.Action, name: "jido_scheduled", schema: []

        def run(params, _context) do
          {:ok, %{received: params.message}}
        end
      end

      defmodule WrapScheduleAgent do
        @moduledoc false
        use Jido.Agent,
          name: "wrap_schedule_agent",
          schema: [
            received: [type: :any, default: nil]
          ]

        def signal_routes(_ctx) do
          [
            {"schedule_atom", ScheduleAtomAction},
            {"jido.scheduled", JidoScheduledAction}
          ]
        end
      end

      {:ok, pid} = AgentServer.start_link(agent: WrapScheduleAgent, jido: jido)

      signal = Signal.new!("schedule_atom", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      # Wait for scheduled atom message (10ms delay + processing)
      state =
        eventually_state(pid, fn state -> state.agent.state.received == :timeout end,
          timeout: 100
        )

      assert state.agent.state.received == :timeout

      GenServer.stop(pid)
    end
  end

  describe "server resolution" do
    test "resolves pid directly", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)
      signal = Signal.new!("increment", %{}, source: "/test")

      {:ok, agent} = AgentServer.call(pid, signal)
      assert agent.state.counter == 1

      GenServer.stop(pid)
    end

    test "resolves via tuple", %{jido: jido} do
      {:ok, _pid} = AgentServer.start_link(agent: TestAgent, id: "via-resolve-test", jido: jido)

      via = AgentServer.via_tuple("via-resolve-test", Jido.registry_name(jido))
      signal = Signal.new!("increment", %{}, source: "/test")

      {:ok, agent} = AgentServer.call(via, signal)
      assert agent.state.counter == 1

      GenServer.stop(AgentServer.whereis(Jido.registry_name(jido), "via-resolve-test"))
    end

    test "resolves string id", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, id: "string-resolve-test", jido: jido)

      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, agent} = AgentServer.call(pid, signal)

      assert agent.state.counter == 1

      GenServer.stop(pid)
    end

    test "returns error for non-existent server", %{jido: jido} do
      registry = Jido.registry_name(jido)

      # Test with string ID that doesn't exist via whereis
      assert AgentServer.whereis(registry, "nonexistent-server") == nil

      # Test that alive? returns false for non-existent string ID lookup
      # (uses whereis internally which returns nil)
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)
      GenServer.stop(pid)
      refute AgentServer.alive?(pid)
    end

    test "returns error for invalid server reference", %{jido: _jido} do
      signal = Signal.new!("increment", %{}, source: "/test")

      assert {:error, :invalid_server} = AgentServer.call(123, signal)
      assert {:error, :invalid_server} = AgentServer.call({:invalid}, signal)
    end

    test "alive? returns false for non-existent server", %{jido: jido} do
      # Start and stop a server to get a dead pid
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)
      GenServer.stop(pid)

      refute AgentServer.alive?(pid)
    end
  end

  describe "error handling" do
    test "unknown call returns error", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)

      result = GenServer.call(pid, :unknown_message)
      assert result == {:error, :unknown_call}

      GenServer.stop(pid)
    end

    test "unknown cast is ignored", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)

      GenServer.cast(pid, :unknown_message)

      # Verify process is still alive and functional
      eventually(fn -> Process.alive?(pid) end)
      GenServer.stop(pid)
    end

    test "unknown info message is ignored", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)

      send(pid, :random_message)

      # Verify process is still alive and functional
      eventually(fn -> Process.alive?(pid) end)
      GenServer.stop(pid)
    end
  end

  describe "agent ID handling" do
    test "uses agent's ID when agent is a struct", %{jido: jido} do
      agent = TestAgent.new(id: "struct-id-123")
      {:ok, pid} = AgentServer.start_link(agent: agent, agent_module: TestAgent, jido: jido)

      {:ok, state} = AgentServer.state(pid)
      assert state.id == "struct-id-123"

      GenServer.stop(pid)
    end

    test "generates ID when not provided", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)
      {:ok, state} = AgentServer.state(pid)

      assert is_binary(state.id)
      assert String.length(state.id) > 0

      GenServer.stop(pid)
    end

    test "converts atom ID to string", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, id: :atom_id, jido: jido)
      {:ok, state} = AgentServer.state(pid)

      assert state.id == "atom_id"

      GenServer.stop(pid)
    end
  end

  describe "child_spec/1" do
    test "returns valid child spec", %{jido: _jido} do
      spec = AgentServer.child_spec(agent: TestAgent, id: "spec-test")

      assert spec.id == "spec-test"
      assert spec.start == {AgentServer, :start_link, [[agent: TestAgent, id: "spec-test"]]}
      assert spec.shutdown == 5_000
      assert spec.restart == :permanent
      assert spec.type == :worker
    end

    test "uses module as default id", %{jido: _jido} do
      spec = AgentServer.child_spec(agent: TestAgent)

      assert spec.id == AgentServer
    end
  end

  describe "termination" do
    defmodule TerminateChildPlugin do
      @moduledoc false
      use Jido.Plugin,
        name: "terminate_child_plugin",
        state_key: :terminate_child_plugin,
        actions: []

      @impl Jido.Plugin
      def child_spec(_config) do
        %{
          id: {__MODULE__, :worker},
          start:
            {Task, :start_link,
             [
               fn ->
                 receive do
                 after
                   86_400_000 -> :ok
                 end
               end
             ]}
        }
      end
    end

    defmodule AgentWithTerminateChildPlugin do
      @moduledoc false
      use Jido.Agent,
        name: "agent_with_terminate_child_plugin",
        schema: [],
        plugins: [TerminateChildPlugin]
    end

    test "terminates cleanly with :normal reason", %{jido: jido} do
      Process.flag(:trap_exit, true)

      {:ok, pid} = AgentServer.start_link(agent: TestAgent, id: "terminate-test", jido: jido)

      GenServer.stop(pid, :normal)
      assert_receive {:EXIT, ^pid, :normal}, 100
      refute Process.alive?(pid)
    end

    test "stops tracked child processes on terminate", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: AgentWithTerminateChildPlugin, jido: jido)

      eventually_state(pid, fn state ->
        map_size(state.children) == 1
      end)

      {:ok, state} = AgentServer.state(pid)
      [{_tag, child}] = Map.to_list(state.children)
      child_pid = child.pid
      child_ref = Process.monitor(child_pid)

      GenServer.stop(pid)

      assert_receive {:DOWN, ^child_ref, :process, ^child_pid, _reason}, 1000
      refute Process.alive?(child_pid)
    end
  end

  describe "drain loop invariant" do
    test "only one drain loop runs at a time", %{jido: jido} do
      defmodule SlowAction2 do
        @moduledoc false
        use Jido.Action,
          name: "slow",
          schema: [
            test_pid: [type: :any, required: false],
            unblock_ref: [type: :any, required: false]
          ]

        def run(params, context) do
          if Map.get(context.state, :blocked_once, false) do
            {:ok, %{processed: true}}
          else
            test_pid = Map.get(params, :test_pid)
            unblock_ref = Map.get(params, :unblock_ref)
            send(test_pid, {:drain_block_started, unblock_ref, self()})

            receive do
              {:unblock_drain, ^unblock_ref} -> :ok
            after
              2_000 -> :ok
            end

            {:ok, %{processed: true, blocked_once: true}}
          end
        end
      end

      defmodule CounterAgent do
        @moduledoc false
        use Jido.Agent,
          name: "counter_agent",
          schema: [
            drain_count: [type: :integer, default: 0],
            blocked_once: [type: :boolean, default: false]
          ]

        def signal_routes(_ctx) do
          [{"slow", SlowAction2}]
        end
      end

      {:ok, pid} = AgentServer.start_link(agent: CounterAgent, jido: jido)
      unblock_ref = make_ref()

      signals =
        for _ <- 1..10 do
          Signal.new!("slow", %{test_pid: self(), unblock_ref: unblock_ref}, source: "/test")
        end

      Enum.each(signals, fn sig -> AgentServer.cast(pid, sig) end)
      assert_receive {:drain_block_started, ^unblock_ref, blocker_pid}, 500

      send(blocker_pid, {:unblock_drain, unblock_ref})

      eventually_state(
        pid,
        fn state ->
          state.status == :idle and state.processing == false and State.queue_empty?(state)
        end,
        timeout: 2000
      )

      {:ok, final_state} = AgentServer.state(pid)

      assert final_state.status == :idle
      assert final_state.processing == false

      assert State.queue_empty?(final_state)

      GenServer.stop(pid)
    end

    test "processing flag prevents concurrent drain loops", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)

      signal = Signal.new!("noop", %{}, source: "/test")
      AgentServer.cast(pid, signal)

      # Wait for processing to complete - status returns to idle and processing flag is false
      eventually_state(pid, fn state ->
        state.processing == false and state.status == :idle
      end)

      GenServer.stop(pid)
    end
  end

  describe "plugin schedules" do
    defmodule ScheduledAction do
      @moduledoc false
      use Jido.Action,
        name: "scheduled_action",
        schema: []

      @impl true
      def run(_params, _context), do: {:ok, %{scheduled: true}}
    end

    defmodule ScheduledPlugin do
      @moduledoc false
      use Jido.Plugin,
        name: "scheduled_plugin",
        state_key: :scheduled_plugin,
        actions: [ScheduledAction],
        schedules: [
          {"* * * * *", ScheduledAction}
        ]
    end

    defmodule AgentWithScheduledPlugin do
      @moduledoc false
      use Jido.Agent,
        name: "agent_with_scheduled_plugin",
        schema: [],
        plugins: [ScheduledPlugin]
    end

    defmodule FastScheduledAction do
      @moduledoc false
      use Jido.Action,
        name: "fast_scheduled_action",
        schema: []

      @impl true
      def run(_params, context) do
        count = Map.get(context.state, :scheduled_count, 0)
        {:ok, %{scheduled_count: count + 1}}
      end
    end

    defmodule FastScheduledPlugin do
      @moduledoc false
      use Jido.Plugin,
        name: "fast_scheduled_plugin",
        state_key: :fast_scheduled_plugin,
        actions: [FastScheduledAction],
        schedules: [
          {"*/1 * * * * *", FastScheduledAction}
        ]
    end

    defmodule AgentWithFastScheduledPlugin do
      @moduledoc false
      use Jido.Agent,
        name: "agent_with_fast_scheduled_plugin",
        schema: [scheduled_count: [type: :integer, default: 0]],
        plugins: [FastScheduledPlugin]
    end

    test "registers plugin schedules on startup", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: AgentWithScheduledPlugin, jido: jido)
      eventually_state(pid, fn state -> map_size(state.cron_jobs) == 1 end)
      {:ok, state} = AgentServer.state(pid)

      assert map_size(state.cron_jobs) == 1

      job_id = {:plugin_schedule, :scheduled_plugin, ScheduledAction}
      assert Map.has_key?(state.cron_jobs, job_id)

      cron_pid = Map.get(state.cron_jobs, job_id)
      assert is_pid(cron_pid)
      assert Process.alive?(cron_pid)

      GenServer.stop(pid)
    end

    test "delivers plugin schedule ticks to the agent", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: AgentWithFastScheduledPlugin, jido: jido)

      eventually_state(
        pid,
        fn state -> map_size(state.cron_jobs) == 1 and state.agent.state.scheduled_count >= 1 end,
        timeout: 2_500
      )

      {:ok, state} = AgentServer.state(pid)
      assert state.agent.state.scheduled_count >= 1

      GenServer.stop(pid)
    end

    test "skips schedules when skip_schedules option is true", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(agent: AgentWithScheduledPlugin, jido: jido, skip_schedules: true)

      {:ok, state} = AgentServer.state(pid)

      assert map_size(state.cron_jobs) == 0

      GenServer.stop(pid)
    end

    test "cleans up cron jobs on termination", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: AgentWithScheduledPlugin, jido: jido)
      eventually_state(pid, fn state -> map_size(state.cron_jobs) == 1 end)
      {:ok, state} = AgentServer.state(pid)

      job_id = {:plugin_schedule, :scheduled_plugin, ScheduledAction}
      cron_pid = Map.get(state.cron_jobs, job_id)
      assert Process.alive?(cron_pid)

      cron_ref = Process.monitor(cron_pid)
      GenServer.stop(pid)

      assert_receive {:DOWN, ^cron_ref, :process, ^cron_pid, _reason}, 1000
      refute Process.alive?(cron_pid)
    end

    test "agent exposes plugin_schedules/0 accessor" do
      schedules = AgentWithScheduledPlugin.plugin_schedules()

      assert length(schedules) == 1
      [spec] = schedules
      assert spec.cron_expression == "* * * * *"
      assert spec.action == ScheduledAction
      assert spec.job_id == {:plugin_schedule, :scheduled_plugin, ScheduledAction}
      assert spec.signal_type == "scheduled_plugin.__schedule__.scheduled_action"
    end

    test "schedule routes are included in plugin_routes/0" do
      routes = AgentWithScheduledPlugin.plugin_routes()

      schedule_route =
        Enum.find(routes, fn {signal_type, _, _} ->
          String.contains?(signal_type, "__schedule__")
        end)

      assert schedule_route != nil
      {signal_type, action, priority} = schedule_route
      assert signal_type == "scheduled_plugin.__schedule__.scheduled_action"
      assert action == ScheduledAction
      assert priority < 0
    end
  end
end
