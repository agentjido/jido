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

  defmodule CustomDirective do
    @moduledoc false
    defstruct [:value]
  end

  setup %{jido: jido} do
    agent = TestAgent.new()

    {:ok, opts} = Options.new(%{agent: agent, id: "test-agent-123", jido: jido})
    {:ok, state} = State.from_options(opts, agent.__struct__, agent)

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

      assert {:ok, new_state} = DirectiveExec.exec(directive, input_signal, state)
      assert Map.has_key?(new_state.children, :worker)
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

      assert {:ok, new_state} = DirectiveExec.exec(directive, input_signal, state)
      assert State.queue_length(new_state) == 1

      assert {{:value, {^input_signal, %Directive.Error{context: :spawn} = error_directive}},
              dequeued_state} = State.dequeue(new_state)

      assert {:ok, ^dequeued_state} =
               DirectiveExec.exec(error_directive, input_signal, dequeued_state)
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

      assert {:ok, new_state} = DirectiveExec.exec(directive, input_signal, state)
      assert Map.has_key?(new_state.children, :worker)
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

    test "does not fallback to legacy global supervisor when jido instance supervisor is missing",
         %{
           input_signal: input_signal,
           agent: agent
         } do
      # Simulate an unrelated legacy global supervisor being present.
      {:ok, _legacy_sup} =
        start_supervised(
          {DynamicSupervisor, strategy: :one_for_one, name: Jido.AgentSupervisor},
          id: {:legacy_agent_supervisor, System.unique_integer([:positive])}
        )

      missing_jido = :"missing_jido_#{System.unique_integer([:positive])}"

      {:ok, opts} =
        Options.new(%{
          agent: agent,
          id: "test-agent-no-fallback",
          jido: missing_jido
        })

      {:ok, state} = State.from_options(opts, agent.__struct__, agent)

      child_spec = {Task, fn -> :ok end}
      directive = %Directive.Spawn{child_spec: child_spec, tag: :worker}

      # Contract: missing instance supervisor should not silently fallback.
      assert {:ok, new_state} = DirectiveExec.exec(directive, input_signal, state)
      refute Map.has_key?(new_state.children, :worker)
      assert State.queue_length(new_state) == 1
    end

    test "tracks spawned child even when tag is nil", %{
      input_signal: input_signal,
      agent: agent,
      jido: jido
    } do
      {:ok, opts} =
        Options.new(%{
          agent: agent,
          id: "test-agent-spawn-auto-tag",
          jido: jido
        })

      {:ok, state} = State.from_options(opts, agent.__struct__, agent)

      child_spec =
        {Task,
         fn ->
           receive do
           after
             86_400_000 -> :ok
           end
         end}

      directive = %Directive.Spawn{child_spec: child_spec, tag: nil}

      assert {:ok, new_state} = DirectiveExec.exec(directive, input_signal, state)
      assert map_size(new_state.children) == 1

      [{tag, child_info}] = Map.to_list(new_state.children)
      assert match?({:spawn, _}, tag)
      assert is_pid(child_info.pid)

      Process.exit(child_info.pid, :kill)
    end
  end

  describe "Schedule directive" do
    test "sends scheduled signal after delay", %{state: state, input_signal: input_signal} do
      signal = Signal.new!(%{type: "scheduled.ping", source: "/test", data: %{}})
      directive = %Directive.Schedule{delay_ms: 10, message: signal}

      assert {:ok, scheduled_state} = DirectiveExec.exec(directive, input_signal, state)
      assert map_size(scheduled_state.scheduled_timers) == 1
      assert_receive {:scheduled_signal, _message_ref, received_signal}, 100
      assert received_signal.type == "scheduled.ping"
    end

    test "wraps non-signal message in signal", %{state: state, input_signal: input_signal} do
      directive = %Directive.Schedule{delay_ms: 10, message: :timeout}

      assert {:ok, scheduled_state} = DirectiveExec.exec(directive, input_signal, state)
      assert map_size(scheduled_state.scheduled_timers) == 1
      assert_receive {:scheduled_signal, _message_ref, received_signal}, 100
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
      assert child_info.meta.role == :worker
      assert child_info.meta.directive == :spawn_agent
      assert is_pid(child_info.pid)

      GenServer.stop(child_info.pid)
    end

    test "spawns child agent with temporary restart semantics", %{
      state: state,
      input_signal: input_signal
    } do
      directive = %Directive.SpawnAgent{
        agent: TestAgent,
        tag: :temporary_child,
        opts: %{},
        meta: %{}
      }

      assert {:ok, new_state} = DirectiveExec.exec(directive, input_signal, state)

      child_info = new_state.children[:temporary_child]
      child_pid = child_info.pid
      child_id = child_info.id
      child_ref = Process.monitor(child_pid)

      Process.exit(child_pid, :kill)
      assert_receive {:DOWN, ^child_ref, :process, ^child_pid, :killed}, 1_000

      eventually(fn ->
        Jido.AgentServer.whereis(state.registry, child_id) == nil
      end)
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

      assert {:ok, new_state} = DirectiveExec.exec(directive, input_signal, state)
      refute Map.has_key?(new_state.children, :failing_child)
      assert State.queue_length(new_state) == 1

      assert {{:value, {^input_signal, %Directive.Error{context: :spawn_agent}}}, _dequeued} =
               State.dequeue(new_state)
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
      assert {:ok, new_state} = DirectiveExec.exec(directive, input_signal, state)
      assert State.queue_length(new_state) == 1
    end
  end

  describe "StopChild directive" do
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
