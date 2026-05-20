defmodule JidoTest.AgentServer.DirectiveExecTest do
  use JidoTest.Case, async: true

  alias Jido.Agent.Directive
  alias Jido.AgentServer.{DirectiveExec, Options, State}
  alias Jido.Sensor.Runtime, as: SensorRuntime
  alias Jido.Signal

  defmodule TestAgent do
    @moduledoc false
    use Jido.Agent,
      name: "directive_exec_test_agent",
      schema: [
        counter: [type: :integer, default: 0]
      ]
  end

  defmodule LifecycleSensor do
    @moduledoc false
    use Jido.Sensor,
      name: "directive_exec_lifecycle_sensor",
      description: "Sensor used to test StartSensor and StopSensor directives",
      schema:
        Zoi.object(
          %{
            label: Zoi.string() |> Zoi.default("default")
          },
          coerce: true
        )

    @impl Jido.Sensor
    def init(config, context) do
      {:ok, %{config: config, context: context}}
    end

    @impl Jido.Sensor
    def handle_event(_event, state), do: {:ok, state}
  end

  defmodule FailingLifecycleSensor do
    @moduledoc false
    use Jido.Sensor,
      name: "directive_exec_failing_lifecycle_sensor",
      description: "Sensor that fails during init",
      schema: Zoi.object(%{}, coerce: true)

    @impl Jido.Sensor
    def init(_config, _context), do: {:error, :init_failed}

    @impl Jido.Sensor
    def handle_event(_event, state), do: {:ok, state}
  end

  defmodule RoundTripSensor do
    @moduledoc false
    use Jido.Sensor,
      name: "directive_exec_round_trip_sensor",
      description: "Sensor used to prove StartSensor delivers signals back to the owning agent",
      schema: Zoi.object(%{}, coerce: true)

    @impl Jido.Sensor
    def init(_config, context) do
      {:ok, %{context: context}}
    end

    @impl Jido.Sensor
    def handle_event(:crash, _state), do: raise("linked sensor crash")

    def handle_event({:trigger, value}, state) do
      signal =
        Signal.new!(%{
          source: "/sensor/directive-round-trip",
          type: "directive.sensor.event",
          data: %{
            value: value,
            agent_id: state.context.agent_id,
            sensor_tag: state.context.sensor_tag
          }
        })

      {:ok, state, [{:emit, signal}]}
    end

    def handle_event(_event, state), do: {:ok, state}
  end

  defmodule StartRoundTripSensorAction do
    @moduledoc false
    use Jido.Action,
      name: "start_round_trip_sensor",
      schema: []

    def run(_params, _context) do
      directive = Directive.start_sensor(:round_trip, RoundTripSensor)
      {:ok, %{sensor_start_requested: true}, [directive]}
    end
  end

  defmodule StartLinkedRoundTripSensorAction do
    @moduledoc false
    use Jido.Action,
      name: "start_linked_round_trip_sensor",
      schema: []

    def run(_params, _context) do
      directive = Directive.start_sensor(:linked_round_trip, RoundTripSensor, link?: true)
      {:ok, %{sensor_start_requested: true}, [directive]}
    end
  end

  defmodule StopRoundTripSensorAction do
    @moduledoc false
    use Jido.Action,
      name: "stop_round_trip_sensor",
      schema: []

    def run(_params, _context) do
      directive = Directive.stop_sensor(:round_trip, :controlled_stop)
      {:ok, %{sensor_stop_requested: true}, [directive]}
    end
  end

  defmodule RecordRoundTripSensorAction do
    @moduledoc false
    use Jido.Action,
      name: "record_round_trip_sensor",
      schema: [
        value: [type: :any, required: true],
        agent_id: [type: :any, required: true],
        sensor_tag: [type: :any, required: true]
      ]

    def run(params, _context) do
      {:ok,
       %{
         last_sensor_value: params.value,
         last_sensor_agent_id: params.agent_id,
         last_sensor_tag: params.sensor_tag
       }}
    end
  end

  defmodule RecordRoundTripSensorExitAction do
    @moduledoc false
    use Jido.Action,
      name: "record_round_trip_sensor_exit",
      schema: [
        tag: [type: :any, required: true],
        reason: [type: :any, required: true]
      ]

    def run(params, context) do
      events = Map.get(context.state, :sensor_exit_events, [])
      {:ok, %{sensor_exit_events: events ++ [params]}}
    end
  end

  defmodule RoundTripSensorAgent do
    @moduledoc false
    use Jido.Agent,
      name: "directive_exec_round_trip_sensor_agent",
      schema: [
        sensor_start_requested: [type: :boolean, default: false],
        sensor_stop_requested: [type: :boolean, default: false],
        last_sensor_value: [type: :any, default: nil],
        last_sensor_agent_id: [type: :any, default: nil],
        last_sensor_tag: [type: :any, default: nil],
        sensor_exit_events: [type: {:list, :any}, default: []]
      ],
      signal_routes: [
        {"directive.sensor.start", StartRoundTripSensorAction},
        {"directive.sensor.stop", StopRoundTripSensorAction},
        {"directive.linked_sensor.start", StartLinkedRoundTripSensorAction},
        {"directive.sensor.event", RecordRoundTripSensorAction},
        {"jido.agent.sensor.exit", RecordRoundTripSensorExitAction}
      ]
  end

  defmodule StopOnSignalAction do
    @moduledoc false
    use Jido.Action,
      name: "stop_on_signal",
      schema: [
        reason: [type: :any, default: :normal]
      ]

    alias Jido.Agent.Directive

    def run(%{reason: reason}, %{state: %{observer_pid: observer_pid}})
        when is_pid(observer_pid) do
      send(observer_pid, {:child_stop_signal_received, reason})
      {:ok, %{stop_reason: reason}, [%Directive.Stop{reason: reason}]}
    end

    def run(%{reason: reason}, _context) do
      {:ok, %{stop_reason: reason}, [%Directive.Stop{reason: reason}]}
    end
  end

  defmodule StopAwareAgent do
    @moduledoc false
    use Jido.Agent,
      name: "directive_exec_stop_aware_agent",
      schema: [
        observer_pid: [type: :any, default: nil],
        stop_reason: [type: :any, default: nil]
      ]

    def signal_routes(_ctx) do
      [
        {"jido.agent.stop", StopOnSignalAction}
      ]
    end
  end

  defmodule CustomDirective do
    @moduledoc false
    defstruct [:value]
  end

  defmodule RunInstructionSuccessAction do
    @moduledoc false
    use Jido.Action,
      name: "run_instruction_success",
      schema: []

    def run(_params, _context), do: {:ok, %{ran: true}}
  end

  defmodule RunInstructionFailureAction do
    @moduledoc false
    use Jido.Action,
      name: "run_instruction_failure",
      schema: []

    def run(_params, _context), do: {:error, :boom}
  end

  defmodule CaptureResultAction do
    @moduledoc false
    use Jido.Action,
      name: "capture_result_action",
      schema: [
        status: [type: :atom, required: true],
        result: [type: :map, default: %{}],
        reason: [type: :any, default: nil],
        effects: [type: :any, default: []],
        instruction: [type: :any, default: nil],
        meta: [type: :map, default: %{}]
      ]

    def run(params, _context) do
      {:ok,
       %{
         captured_status: params.status,
         captured_result: params.result,
         captured_reason: params.reason,
         captured_meta: params.meta
       }}
    end
  end

  defmodule CaptureResultEmitAction do
    @moduledoc false
    use Jido.Action,
      name: "capture_result_emit_action",
      schema: [
        status: [type: :atom, required: true],
        result: [type: :map, default: %{}],
        reason: [type: :any, default: nil],
        effects: [type: :any, default: []],
        instruction: [type: :any, default: nil],
        meta: [type: :map, default: %{}]
      ]

    def run(_params, _context) do
      directive = Directive.emit(%{type: "capture.result.event"})
      {:ok, %{captured_emit: true}, [directive]}
    end
  end

  setup %{jido: jido} do
    agent = TestAgent.new()

    {:ok, opts} = Options.new(%{agent: agent, id: "test-agent-123", jido: jido})
    {:ok, state} = State.from_options(opts, TestAgent, agent)

    input_signal = Signal.new!(%{type: "test.signal", source: "/test", data: %{}})

    %{state: state, input_signal: input_signal, agent: agent}
  end

  describe "Emit directive" do
    test "falls back to dispatching to current process when no dispatch config", %{
      state: state,
      input_signal: input_signal
    } do
      signal = Signal.new!(%{type: "test.emitted", source: "/test", data: %{}})
      directive = %Directive.Emit{signal: signal, dispatch: nil}

      assert {:async, nil, ^state} = DirectiveExec.exec(directive, input_signal, state)
      assert_receive {:signal, %Signal{type: "test.emitted"}}
    end

    test "returns async tuple when dispatch config provided", %{
      state: state,
      input_signal: input_signal
    } do
      signal = Signal.new!(%{type: "test.emitted", source: "/test", data: %{}})
      directive = %Directive.Emit{signal: signal, dispatch: {:logger, level: :info}}

      assert {:async, nil, ^state} = DirectiveExec.exec(directive, input_signal, state)
    end

    test "uses default_dispatch from state when directive dispatch is nil", %{
      input_signal: input_signal,
      agent: agent,
      jido: jido
    } do
      {:ok, opts} =
        Options.new(%{
          agent: agent,
          id: "test-agent-dispatch",
          default_dispatch: {:logger, level: :debug},
          jido: jido
        })

      {:ok, state} = State.from_options(opts, agent.__struct__, agent)

      signal = Signal.new!(%{type: "test.emitted", source: "/test", data: %{}})
      directive = %Directive.Emit{signal: signal, dispatch: nil}

      assert {:async, nil, ^state} = DirectiveExec.exec(directive, input_signal, state)
    end
  end

  describe "Error directive" do
    test "returns ok with log_only policy", %{state: state, input_signal: input_signal} do
      error = Jido.Error.validation_error("Test error")
      directive = %Directive.Error{error: error, context: :test}

      assert {:ok, ^state} = DirectiveExec.exec(directive, input_signal, state)
    end

    test "returns stop with stop_on_error policy", %{
      input_signal: input_signal,
      agent: agent,
      jido: jido
    } do
      {:ok, opts} =
        Options.new(%{
          agent: agent,
          id: "test-agent-stop",
          error_policy: :stop_on_error,
          jido: jido
        })

      {:ok, state} = State.from_options(opts, agent.__struct__, agent)

      error = Jido.Error.validation_error("Test error")
      directive = %Directive.Error{error: error, context: :test}

      assert {:stop, {:agent_error, ^error}, ^state} =
               DirectiveExec.exec(directive, input_signal, state)
    end

    test "increments error_count with max_errors policy", %{
      input_signal: input_signal,
      agent: agent,
      jido: jido
    } do
      {:ok, opts} =
        Options.new(%{
          agent: agent,
          id: "test-agent-max",
          error_policy: {:max_errors, 3},
          jido: jido
        })

      {:ok, state} = State.from_options(opts, agent.__struct__, agent)
      assert state.error_count == 0

      error = Jido.Error.validation_error("Test error")
      directive = %Directive.Error{error: error, context: :test}

      {:ok, state} = DirectiveExec.exec(directive, input_signal, state)
      assert state.error_count == 1

      {:ok, state} = DirectiveExec.exec(directive, input_signal, state)
      assert state.error_count == 2

      {:stop, {:max_errors_exceeded, 3}, state} =
        DirectiveExec.exec(directive, input_signal, state)

      assert state.error_count == 3
    end
  end

  describe "Spawn directive" do
    test "spawns child using custom spawn_fun", %{
      input_signal: input_signal,
      agent: agent,
      jido: jido
    } do
      test_pid = self()

      spawn_fun = fn child_spec ->
        send(test_pid, {:spawn_called, child_spec})
        {:ok, spawn(fn -> :ok end)}
      end

      {:ok, opts} =
        Options.new(%{
          agent: agent,
          id: "test-agent-spawn",
          spawn_fun: spawn_fun,
          jido: jido
        })

      {:ok, state} = State.from_options(opts, agent.__struct__, agent)

      child_spec = {Task, fn -> :ok end}
      directive = %Directive.Spawn{child_spec: child_spec, tag: :worker}

      assert {:ok, ^state} = DirectiveExec.exec(directive, input_signal, state)
      assert_receive {:spawn_called, ^child_spec}
    end

    test "handles spawn failure gracefully", %{
      input_signal: input_signal,
      agent: agent,
      jido: jido
    } do
      spawn_fun = fn _child_spec ->
        {:error, :spawn_failed}
      end

      {:ok, opts} =
        Options.new(%{
          agent: agent,
          id: "test-agent-spawn-fail",
          spawn_fun: spawn_fun,
          jido: jido
        })

      {:ok, state} = State.from_options(opts, agent.__struct__, agent)

      child_spec = {Task, fn -> :ok end}
      directive = %Directive.Spawn{child_spec: child_spec, tag: :worker}

      assert {:ok, ^state} = DirectiveExec.exec(directive, input_signal, state)
    end

    test "handles spawn returning {:ok, pid, info} tuple", %{
      input_signal: input_signal,
      agent: agent,
      jido: jido
    } do
      test_pid = self()

      spawn_fun = fn child_spec ->
        send(test_pid, {:spawn_called, child_spec})
        {:ok, spawn(fn -> :ok end), %{extra: :info}}
      end

      {:ok, opts} =
        Options.new(%{
          agent: agent,
          id: "test-agent-spawn-info",
          spawn_fun: spawn_fun,
          jido: jido
        })

      {:ok, state} = State.from_options(opts, agent.__struct__, agent)

      child_spec = {Task, fn -> :ok end}
      directive = %Directive.Spawn{child_spec: child_spec, tag: :worker}

      assert {:ok, ^state} = DirectiveExec.exec(directive, input_signal, state)
      assert_receive {:spawn_called, ^child_spec}
    end

    test "handles spawn returning :ignored", %{
      input_signal: input_signal,
      agent: agent,
      jido: jido
    } do
      spawn_fun = fn _child_spec ->
        :ignored
      end

      {:ok, opts} =
        Options.new(%{
          agent: agent,
          id: "test-agent-spawn-ignored",
          spawn_fun: spawn_fun,
          jido: jido
        })

      {:ok, state} = State.from_options(opts, agent.__struct__, agent)

      child_spec = {Task, fn -> :ok end}
      directive = %Directive.Spawn{child_spec: child_spec, tag: :worker}

      assert {:ok, ^state} = DirectiveExec.exec(directive, input_signal, state)
    end
  end

  describe "RunInstruction directive" do
    test "executes instruction and routes result via result_action", %{
      state: state,
      input_signal: input_signal
    } do
      instruction = Jido.Instruction.new!(%{action: RunInstructionSuccessAction})

      directive =
        Directive.run_instruction(instruction,
          result_action: CaptureResultAction,
          meta: %{source: :test}
        )

      assert {:ok, state} = DirectiveExec.exec(directive, input_signal, state)

      assert state.agent.state.captured_status == :ok
      assert state.agent.state.captured_result == %{ran: true}
      assert state.agent.state.captured_reason == nil
      assert state.agent.state.captured_meta == %{source: :test}
      assert State.queue_length(state) == 0
    end

    test "normalizes failures and enqueues directives from result_action", %{
      state: state,
      input_signal: input_signal
    } do
      instruction = Jido.Instruction.new!(%{action: RunInstructionFailureAction})

      directive =
        Directive.run_instruction(instruction,
          result_action: CaptureResultEmitAction
        )

      assert {:ok, state} = DirectiveExec.exec(directive, input_signal, state)
      assert state.agent.state.captured_emit == true
      assert State.queue_length(state) == 1

      assert {{:value, {^input_signal, %Directive.Emit{signal: %{type: "capture.result.event"}}}},
              _state} = State.dequeue(state)
    end
  end

  describe "Schedule directive" do
    test "sends scheduled signal after delay", %{state: state, input_signal: input_signal} do
      signal = Signal.new!(%{type: "scheduled.ping", source: "/test", data: %{}})
      directive = %Directive.Schedule{delay_ms: 10, message: signal}

      assert {:ok, ^state} = DirectiveExec.exec(directive, input_signal, state)
      assert_receive {:scheduled_signal, received_signal}, 100
      assert received_signal.type == "scheduled.ping"
    end

    test "wraps non-signal message in signal", %{state: state, input_signal: input_signal} do
      directive = %Directive.Schedule{delay_ms: 10, message: :timeout}

      assert {:ok, ^state} = DirectiveExec.exec(directive, input_signal, state)
      assert_receive {:scheduled_signal, received_signal}, 100
      assert received_signal.type == "jido.scheduled"
      assert received_signal.data.message == :timeout
    end
  end

  describe "Stop directive" do
    test "returns stop tuple with reason", %{state: state, input_signal: input_signal} do
      directive = %Directive.Stop{reason: :normal}

      assert {:stop, :normal, ^state} = DirectiveExec.exec(directive, input_signal, state)
    end

    test "returns stop tuple with custom reason", %{state: state, input_signal: input_signal} do
      directive = %Directive.Stop{reason: {:shutdown, :user_requested}}

      assert {:stop, {:shutdown, :user_requested}, ^state} =
               DirectiveExec.exec(directive, input_signal, state)
    end
  end

  describe "SpawnAgent directive" do
    test "spawns child agent with module", %{state: state, input_signal: input_signal} do
      directive = %Directive.SpawnAgent{
        agent: TestAgent,
        tag: :child_worker,
        opts: %{},
        meta: %{role: :worker}
      }

      assert {:ok, new_state} = DirectiveExec.exec(directive, input_signal, state)
      assert Map.has_key?(new_state.children, :child_worker)
      child_info = new_state.children[:child_worker]
      assert child_info.module == TestAgent
      assert child_info.tag == :child_worker
      assert child_info.meta == %{role: :worker}
      assert is_pid(child_info.pid)

      GenServer.stop(child_info.pid)
    end

    test "spawns child agent with struct agent (resolve_agent_module for struct)", %{
      state: state,
      input_signal: input_signal
    } do
      agent_struct = TestAgent.new()

      directive = %Directive.SpawnAgent{
        agent: agent_struct,
        tag: :struct_child,
        opts: %{},
        meta: %{}
      }

      assert {:ok, new_state} = DirectiveExec.exec(directive, input_signal, state)
      assert Map.has_key?(new_state.children, :struct_child)
      child_info = new_state.children[:struct_child]
      # resolve_agent_module extracts __struct__ from the agent struct
      assert child_info.module == agent_struct.__struct__
      assert is_pid(child_info.pid)

      # Stop the child without relying on catch_exit's generated AST handling.
      if Process.alive?(child_info.pid) do
        try do
          GenServer.stop(child_info.pid, :normal, 100)
        catch
          :exit, _ -> :ok
        end
      end
    end

    test "handles spawn failure gracefully", %{state: state, input_signal: input_signal} do
      directive = %Directive.SpawnAgent{
        agent: NonExistentAgentModule,
        tag: :failing_child,
        opts: %{},
        meta: %{}
      }

      assert {:ok, ^state} = DirectiveExec.exec(directive, input_signal, state)
      refute Map.has_key?(state.children, :failing_child)
    end

    test "resolve_agent_module handles non-module non-struct agent (unknown type)", %{
      state: state,
      input_signal: input_signal
    } do
      # Pass a string as agent to hit the fallback resolve_agent_module/1 clause
      directive = %Directive.SpawnAgent{
        agent: "not_a_module_or_struct",
        tag: :unknown_agent,
        opts: %{},
        meta: %{}
      }

      # This will fail to spawn but should handle gracefully
      assert {:ok, ^state} = DirectiveExec.exec(directive, input_signal, state)
    end

    test "rejects unsupported lifecycle opts even for raw SpawnAgent structs", %{
      state: state,
      input_signal: input_signal
    } do
      directive = %Directive.SpawnAgent{
        agent: TestAgent,
        tag: :managed_child,
        opts: %{storage: Jido.Storage.ETS, idle_timeout: 5_000},
        meta: %{}
      }

      assert {:ok, ^state} = DirectiveExec.exec(directive, input_signal, state)
      refute Map.has_key?(state.children, :managed_child)
    end

    test "rejects malformed opts even for raw SpawnAgent structs", %{
      state: state,
      input_signal: input_signal
    } do
      directive = %Directive.SpawnAgent{
        agent: TestAgent,
        tag: :bad_opts_child,
        opts: [:not_a_map],
        meta: %{}
      }

      assert {:ok, ^state} = DirectiveExec.exec(directive, input_signal, state)
      refute Map.has_key?(state.children, :bad_opts_child)
    end
  end

  describe "StopChild directive" do
    test "sends jido.agent.stop to child", %{state: state, input_signal: input_signal} do
      spawn_directive = %Directive.SpawnAgent{
        agent: StopAwareAgent,
        tag: :stop_signal_child,
        opts: %{initial_state: %{observer_pid: self()}},
        meta: %{}
      }

      {:ok, state_with_child} = DirectiveExec.exec(spawn_directive, input_signal, state)
      assert Map.has_key?(state_with_child.children, :stop_signal_child)
      child_pid = state_with_child.children[:stop_signal_child].pid
      child_ref = Process.monitor(child_pid)

      stop_directive = %Directive.StopChild{tag: :stop_signal_child, reason: :shutdown}

      assert {:ok, ^state_with_child} =
               DirectiveExec.exec(stop_directive, input_signal, state_with_child)

      assert_receive {:child_stop_signal_received, :shutdown}, 1_000
      assert_receive {:DOWN, ^child_ref, :process, ^child_pid, :shutdown}, 1_000
    end

    test "wraps custom stop reasons as clean shutdowns", %{
      state: state,
      input_signal: input_signal
    } do
      spawn_directive = %Directive.SpawnAgent{
        agent: StopAwareAgent,
        tag: :custom_reason_child,
        opts: %{initial_state: %{observer_pid: self()}},
        meta: %{}
      }

      {:ok, state_with_child} = DirectiveExec.exec(spawn_directive, input_signal, state)
      child_pid = state_with_child.children[:custom_reason_child].pid
      child_ref = Process.monitor(child_pid)

      stop_directive = %Directive.StopChild{tag: :custom_reason_child, reason: :cleanup}

      assert {:ok, ^state_with_child} =
               DirectiveExec.exec(stop_directive, input_signal, state_with_child)

      assert_receive {:child_stop_signal_received, {:shutdown, :cleanup}}, 1_000
      assert_receive {:DOWN, ^child_ref, :process, ^child_pid, {:shutdown, :cleanup}}, 1_000
    end

    test "stops existing child", %{state: state, input_signal: input_signal} do
      spawn_directive = %Directive.SpawnAgent{
        agent: TestAgent,
        tag: :child_to_stop,
        opts: %{},
        meta: %{}
      }

      {:ok, state_with_child} = DirectiveExec.exec(spawn_directive, input_signal, state)
      assert Map.has_key?(state_with_child.children, :child_to_stop)
      child_pid = state_with_child.children[:child_to_stop].pid

      stop_directive = %Directive.StopChild{tag: :child_to_stop, reason: :normal}

      assert {:ok, ^state_with_child} =
               DirectiveExec.exec(stop_directive, input_signal, state_with_child)

      refute_eventually(Process.alive?(child_pid))
    end

    test "returns ok when child tag not found", %{state: state, input_signal: input_signal} do
      directive = %Directive.StopChild{tag: :nonexistent_child, reason: :normal}

      assert {:ok, ^state} = DirectiveExec.exec(directive, input_signal, state)
    end
  end

  describe "StartSensor and StopSensor directives" do
    test "starts a tagged sensor runtime", %{state: state, input_signal: input_signal} do
      directive =
        Directive.start_sensor(:market_data, LifecycleSensor,
          config: %{label: "prices"},
          meta: %{purpose: :quotes}
        )

      assert {:ok, new_state} = DirectiveExec.exec(directive, input_signal, state)

      key = {:sensor, :market_data}
      assert Map.has_key?(new_state.children, key)

      child_info = new_state.children[key]
      assert child_info.module == LifecycleSensor
      assert child_info.tag == key
      assert child_info.meta.kind == :sensor
      assert child_info.meta.sensor == LifecycleSensor
      assert child_info.meta.sensor_tag == :market_data
      assert child_info.meta.purpose == :quotes
      assert Process.alive?(child_info.pid)

      runtime_state = :sys.get_state(child_info.pid)
      assert runtime_state.config.label == "prices"
      assert runtime_state.context.agent_id == state.id
      assert runtime_state.context.sensor_tag == :market_data
      assert runtime_state.context.sensor_origin == :directive

      GenServer.stop(child_info.pid)
    end

    test "sensor started by directive emits back into the owning agent", context do
      pid =
        start_server(context, RoundTripSensorAgent, id: unique_id("directive-sensor-round-trip"))

      start_signal =
        Signal.new!(%{
          source: "/test",
          type: "directive.sensor.start",
          data: %{}
        })

      assert :ok = Jido.AgentServer.cast(pid, start_signal)

      state =
        eventually_state(pid, fn state ->
          state.agent.state.sensor_start_requested == true and
            Map.has_key?(state.children, {:sensor, :round_trip})
        end)

      child_info = state.children[{:sensor, :round_trip}]
      assert child_info.module == RoundTripSensor
      assert Process.alive?(child_info.pid)

      assert :ok = SensorRuntime.event(child_info.pid, {:trigger, :from_sensor})

      state =
        eventually_state(pid, fn state ->
          state.agent.state.last_sensor_value == :from_sensor
        end)

      assert state.agent.state.last_sensor_agent_id == state.id
      assert state.agent.state.last_sensor_tag == :round_trip

      GenServer.stop(pid)
    end

    test "controlled stop does not emit sensor exit lifecycle signal", context do
      pid =
        start_server(context, RoundTripSensorAgent,
          id: unique_id("directive-sensor-controlled-stop")
        )

      start_signal = Signal.new!(%{source: "/test", type: "directive.sensor.start", data: %{}})
      stop_signal = Signal.new!(%{source: "/test", type: "directive.sensor.stop", data: %{}})

      assert :ok = Jido.AgentServer.cast(pid, start_signal)

      state =
        eventually_state(pid, fn state ->
          Map.has_key?(state.children, {:sensor, :round_trip})
        end)

      sensor_pid = state.children[{:sensor, :round_trip}].pid
      sensor_ref = Process.monitor(sensor_pid)

      assert :ok = Jido.AgentServer.cast(pid, stop_signal)

      assert_receive {:DOWN, ^sensor_ref, :process, ^sensor_pid, {:shutdown, :controlled_stop}},
                     1_000

      state =
        eventually_state(pid, fn state ->
          state.agent.state.sensor_stop_requested == true and
            not Map.has_key?(state.children, {:sensor, :round_trip})
        end)

      assert state.agent.state.sensor_exit_events == []

      GenServer.stop(pid)
    end

    test "unlinked directive sensor stops when the owning agent exits abnormally", context do
      previous_trap_exit = Process.flag(:trap_exit, true)

      try do
        pid =
          start_server(context, RoundTripSensorAgent,
            id: unique_id("directive-sensor-owner-down")
          )

        start_signal =
          Signal.new!(%{
            source: "/test",
            type: "directive.sensor.start",
            data: %{}
          })

        assert :ok = Jido.AgentServer.cast(pid, start_signal)

        state =
          eventually_state(pid, fn state ->
            Map.has_key?(state.children, {:sensor, :round_trip})
          end)

        sensor_pid = state.children[{:sensor, :round_trip}].pid
        sensor_ref = Process.monitor(sensor_pid)

        Process.exit(pid, :kill)

        assert_receive {:EXIT, ^pid, :killed}, 500

        assert_receive {:DOWN, ^sensor_ref, :process, ^sensor_pid, {:owner_down, :killed}},
                       1_000
      after
        Process.flag(:trap_exit, previous_trap_exit)
      end
    end

    test "link? true makes sensor failure fail the owning agent", context do
      previous_trap_exit = Process.flag(:trap_exit, true)

      try do
        pid =
          start_server(context, RoundTripSensorAgent, id: unique_id("directive-linked-sensor"))

        start_signal =
          Signal.new!(%{
            source: "/test",
            type: "directive.linked_sensor.start",
            data: %{}
          })

        assert :ok = Jido.AgentServer.cast(pid, start_signal)

        state =
          eventually_state(pid, fn state ->
            Map.has_key?(state.children, {:sensor, :linked_round_trip})
          end)

        sensor_pid = state.children[{:sensor, :linked_round_trip}].pid
        agent_ref = Process.monitor(pid)

        assert :ok = SensorRuntime.event(sensor_pid, :crash)

        assert_receive {:DOWN, ^agent_ref, :process, ^pid,
                        {%RuntimeError{message: "linked sensor crash"}, _stack}},
                       1_000
      after
        Process.flag(:trap_exit, previous_trap_exit)
      end
    end

    test "leaves state unchanged when sensor init fails", %{
      state: state,
      input_signal: input_signal
    } do
      directive = Directive.start_sensor(:bad_sensor, FailingLifecycleSensor)

      assert {:ok, ^state} = DirectiveExec.exec(directive, input_signal, state)
      refute Map.has_key?(state.children, {:sensor, :bad_sensor})
    end

    test "replaces an existing sensor by default", %{state: state, input_signal: input_signal} do
      start_a =
        Directive.start_sensor(:replaceable, LifecycleSensor, config: %{label: "a"})

      {:ok, state_with_sensor} = DirectiveExec.exec(start_a, input_signal, state)
      old_pid = state_with_sensor.children[{:sensor, :replaceable}].pid

      start_b =
        Directive.start_sensor(:replaceable, LifecycleSensor, config: %{label: "b"})

      assert {:ok, replaced_state} = DirectiveExec.exec(start_b, input_signal, state_with_sensor)

      new_pid = replaced_state.children[{:sensor, :replaceable}].pid
      assert new_pid != old_pid
      assert Process.alive?(new_pid)
      refute_eventually(Process.alive?(old_pid))
      assert :sys.get_state(new_pid).config.label == "b"

      GenServer.stop(new_pid)
    end

    test "does not replace an existing sensor when replace? is false", %{
      state: state,
      input_signal: input_signal
    } do
      start_a =
        Directive.start_sensor(:sticky, LifecycleSensor, config: %{label: "a"})

      {:ok, state_with_sensor} = DirectiveExec.exec(start_a, input_signal, state)
      old_pid = state_with_sensor.children[{:sensor, :sticky}].pid

      start_b =
        Directive.start_sensor(:sticky, LifecycleSensor,
          config: %{label: "b"},
          replace?: false
        )

      assert {:ok, unchanged_state} = DirectiveExec.exec(start_b, input_signal, state_with_sensor)

      assert unchanged_state.children[{:sensor, :sticky}].pid == old_pid
      assert :sys.get_state(old_pid).config.label == "a"

      GenServer.stop(old_pid)
    end

    test "replaces linked sensors without propagating controlled stop exits", %{
      state: state,
      input_signal: input_signal
    } do
      previous_trap_exit = Process.flag(:trap_exit, true)

      try do
        start_a =
          Directive.start_sensor(:linked_replaceable, LifecycleSensor,
            config: %{label: "a"},
            link?: true
          )

        {:ok, state_with_sensor} = DirectiveExec.exec(start_a, input_signal, state)
        old_pid = state_with_sensor.children[{:sensor, :linked_replaceable}].pid

        start_b =
          Directive.start_sensor(:linked_replaceable, LifecycleSensor,
            config: %{label: "b"},
            link?: true
          )

        assert {:ok, replaced_state} =
                 DirectiveExec.exec(start_b, input_signal, state_with_sensor)

        new_pid = replaced_state.children[{:sensor, :linked_replaceable}].pid
        assert new_pid != old_pid
        assert Process.alive?(new_pid)
        refute_receive {:EXIT, ^old_pid, {:shutdown, :replace}}, 100
        refute_eventually(Process.alive?(old_pid))
        assert :sys.get_state(new_pid).config.label == "b"

        GenServer.stop(new_pid)
      after
        Process.flag(:trap_exit, previous_trap_exit)
      end
    end

    test "stops linked sensors without propagating controlled stop exits", %{
      state: state,
      input_signal: input_signal
    } do
      previous_trap_exit = Process.flag(:trap_exit, true)

      try do
        start_directive =
          Directive.start_sensor(:linked_temporary, LifecycleSensor, link?: true)

        {:ok, state_with_sensor} = DirectiveExec.exec(start_directive, input_signal, state)
        sensor_pid = state_with_sensor.children[{:sensor, :linked_temporary}].pid
        sensor_ref = Process.monitor(sensor_pid)

        stop_directive = Directive.stop_sensor(:linked_temporary, :cleanup)

        assert {:ok, stopped_state} =
                 DirectiveExec.exec(stop_directive, input_signal, state_with_sensor)

        refute Map.has_key?(stopped_state.children, {:sensor, :linked_temporary})

        assert_receive {:DOWN, ^sensor_ref, :process, ^sensor_pid, {:shutdown, :cleanup}},
                       1_000

        refute_receive {:EXIT, ^sensor_pid, _reason}, 100
      after
        Process.flag(:trap_exit, previous_trap_exit)
      end
    end

    test "does not stop existing sensor when replacement module is invalid", %{
      state: state,
      input_signal: input_signal
    } do
      start_directive =
        Directive.start_sensor(:protected, LifecycleSensor, config: %{label: "active"})

      {:ok, state_with_sensor} = DirectiveExec.exec(start_directive, input_signal, state)
      old_pid = state_with_sensor.children[{:sensor, :protected}].pid

      invalid_replacement =
        Directive.start_sensor(:protected, NonExistentSensorModule, config: %{label: "bad"})

      assert {:ok, unchanged_state} =
               DirectiveExec.exec(invalid_replacement, input_signal, state_with_sensor)

      assert unchanged_state.children[{:sensor, :protected}].pid == old_pid
      assert Process.alive?(old_pid)
      assert :sys.get_state(old_pid).config.label == "active"

      GenServer.stop(old_pid)
    end

    test "stops an existing tagged sensor", %{state: state, input_signal: input_signal} do
      start_directive = Directive.start_sensor(:temporary, LifecycleSensor)
      {:ok, state_with_sensor} = DirectiveExec.exec(start_directive, input_signal, state)

      sensor_pid = state_with_sensor.children[{:sensor, :temporary}].pid

      stop_directive = Directive.stop_sensor(:temporary, :cleanup)

      assert {:ok, stopped_state} =
               DirectiveExec.exec(stop_directive, input_signal, state_with_sensor)

      refute Map.has_key?(stopped_state.children, {:sensor, :temporary})
      refute_eventually(Process.alive?(sensor_pid))
    end

    test "returns ok when sensor tag is not found", %{state: state, input_signal: input_signal} do
      directive = Directive.stop_sensor(:missing_sensor)

      assert {:ok, ^state} = DirectiveExec.exec(directive, input_signal, state)
    end
  end

  describe "Any (fallback) directive" do
    test "returns ok for unknown directive types", %{state: state, input_signal: input_signal} do
      directive = %CustomDirective{value: 42}

      assert {:ok, ^state} = DirectiveExec.exec(directive, input_signal, state)
    end
  end
end
