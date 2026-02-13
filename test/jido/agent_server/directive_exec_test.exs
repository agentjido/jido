defmodule JidoTest.AgentServer.DirectiveExecTest do
  use JidoTest.Case, async: true

  alias Jido.Agent.Directive
  alias Jido.AgentServer.{DirectiveExec, Options, State}
  alias Jido.Signal

  defmodule TestAgent do
    @moduledoc false
    use Jido.Agent,
      name: "directive_exec_test_agent",
      schema: [
        counter: [type: :integer, default: 0]
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
    test "returns async tuple with nil ref when no dispatch config", %{
      state: state,
      input_signal: input_signal
    } do
      signal = Signal.new!(%{type: "test.emitted", source: "/test", data: %{}})
      directive = %Directive.Emit{signal: signal, dispatch: nil}

      assert {:async, nil, ^state} = DirectiveExec.exec(directive, input_signal, state)
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

      # Stop the child - catch potential exit as process may be in init
      catch_exit do
        GenServer.stop(child_info.pid, :normal, 100)
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

  describe "Any (fallback) directive" do
    test "returns ok for unknown directive types", %{state: state, input_signal: input_signal} do
      directive = %CustomDirective{value: 42}

      assert {:ok, ^state} = DirectiveExec.exec(directive, input_signal, state)
    end
  end
end
