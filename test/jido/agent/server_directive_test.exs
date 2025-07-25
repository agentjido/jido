defmodule Jido.Agent.Server.DirectiveTest do
  use JidoTest.Case, async: true
  alias Jido.Agent.Server.{Directive, State, Signal}
  alias JidoTest.TestAgents.BasicAgent
  alias Jido.Error

  alias Jido.Agent.Directive.{
    Spawn,
    Kill,
    RegisterAction,
    DeregisterAction,
    StateModification
  }

  @moduletag :capture_log

  # Helper to compare Error structs ignoring stacktrace
  defp assert_error_match(actual, expected) do
    assert Exception.exception?(actual)
    actual_map = Error.to_map(actual)
    expected_map = Error.to_map(expected)
    assert actual_map.type == expected_map.type
    assert actual_map.message == expected_map.message
    assert actual_map.details == expected_map.details
  end

  setup do
    {:ok, supervisor} = start_supervised(DynamicSupervisor)
    agent = %{BasicAgent.new("test") | state: %{config: %{}}}

    state = %State{
      agent: agent,
      child_supervisor: supervisor,
      dispatch: [
        {:pid, [target: self(), delivery_mode: :async]}
      ],
      status: :idle,
      pending_signals: :queue.new()
    }

    {:ok, state: state}
  end

  describe "handle/2" do
    test "processes multiple directives in sequence", %{state: state} do
      task1 = fn -> Process.sleep(1000) end
      task2 = fn -> Process.sleep(1000) end

      directives = [
        %Spawn{module: Task, args: task1},
        %Spawn{module: Task, args: task2}
      ]

      {:ok, new_state} = Directive.handle(state, directives)
      assert state == new_state

      # Verify we received process_started signals for both tasks
      assert_receive {:signal, signal1}
      assert signal1.type == Signal.process_started()
      assert is_pid(signal1.data.child_pid)

      assert_receive {:signal, signal2}
      assert signal2.type == Signal.process_started()
      assert is_pid(signal2.data.child_pid)
    end

    test "stops processing on first error", %{state: state} do
      task = fn -> Process.sleep(1000) end

      directives = [
        %Spawn{module: Task, args: task},
        :invalid_directive
      ]

      {:error, error} = Directive.handle(state, directives)

      # Should only receive one process_started signal
      assert_receive {:signal, signal}
      assert signal.type == Signal.process_started()
      refute_receive {:signal, _}

      assert_error_match(
        error,
        Error.validation_error("Invalid directive", %{directive: :invalid_directive})
      )
    end

    test "handles single directive", %{state: state} do
      task = fn -> Process.sleep(350) end
      directive = %Spawn{module: Task, args: task}

      {:ok, new_state} = Directive.handle(state, directive)
      assert state == new_state

      assert_receive {:signal, signal}
      assert signal.type == Signal.process_started()
      assert is_pid(signal.data.child_pid)
    end
  end

  describe "process management directives" do
    test "spawn creates a new child process", %{state: state} do
      task = fn -> Process.sleep(1000) end
      directive = %Spawn{module: Task, args: task}
      {:ok, new_state} = Directive.execute(state, directive)
      assert state == new_state

      # Verify we received the process_started signal
      assert_receive {:signal, signal}
      assert signal.type == Signal.process_started()
      assert is_pid(signal.data.child_pid)

      assert signal.data.child_spec == %{
               id: signal.data.child_spec.id,
               start: {Task, :start_link, [task]},
               restart: :temporary,
               type: :worker
             }
    end

    test "kill terminates a specific process", %{state: state} do
      task = fn -> Process.sleep(1000) end
      spawn_directive = %Spawn{module: Task, args: task}
      {:ok, state} = Directive.execute(state, spawn_directive)

      # Clear the spawn signal
      assert_receive {:signal, _}

      # Get the PID from the state's child processes
      pid = DynamicSupervisor.which_children(state.child_supervisor) |> hd() |> elem(1)
      assert Process.alive?(pid)

      kill_directive = %Kill{pid: pid}
      {:ok, new_state} = Directive.execute(state, kill_directive)
      refute Process.alive?(pid)
      assert state == new_state

      # Verify we received the process_terminated signal
      assert_receive {:signal, signal}
      assert signal.type == Signal.process_terminated()
      assert signal.data.child_pid == pid
    end

    test "kill returns error for non-existent process", %{state: state} do
      non_existent_pid = spawn(fn -> :ok end)
      Process.exit(non_existent_pid, :kill)

      directive = %Kill{pid: non_existent_pid}
      {:error, error} = Directive.execute(state, directive)

      assert_error_match(
        error,
        Error.execution_error("Process not found", %{pid: non_existent_pid})
      )
    end
  end

  describe "agent modification directives" do
    test "register_action adds action module to agent", %{state: state} do
      directive = %RegisterAction{action_module: MyAction}
      {:ok, updated_state} = Directive.execute(state, directive)

      # Verify action module was added to agent's actions
      assert MyAction in updated_state.agent.actions

      # Registering same module again should not duplicate it
      {:ok, final_state} = Directive.execute(updated_state, directive)
      assert MyAction in final_state.agent.actions
      assert length(final_state.agent.actions) == length(updated_state.agent.actions)
    end

    test "deregister_action removes action module from agent", %{state: state} do
      # First register the action
      {:ok, state_with_action} =
        Directive.execute(state, %RegisterAction{action_module: MyAction})

      assert MyAction in state_with_action.agent.actions

      # Then deregister it
      directive = %DeregisterAction{action_module: MyAction}
      {:ok, updated_state} = Directive.execute(state_with_action, directive)

      # Verify action module was removed
      refute MyAction in updated_state.agent.actions
    end

    test "state_modification updates agent state", %{state: state} do
      # Test :set operation
      set_directive = %StateModification{
        op: :set,
        path: [:config, :mode],
        value: :active
      }

      {:ok, state_after_set} = Directive.execute(state, set_directive)
      assert get_in(state_after_set.agent.state, [:config, :mode]) == :active

      # Test :update operation
      update_directive = %StateModification{
        op: :update,
        path: [:config, :mode],
        value: fn _ -> :inactive end
      }

      {:ok, state_after_update} = Directive.execute(state_after_set, update_directive)
      assert get_in(state_after_update.agent.state, [:config, :mode]) == :inactive

      # Test :delete operation
      delete_directive = %StateModification{
        op: :delete,
        path: [:config, :mode]
      }

      {:ok, state_after_delete} = Directive.execute(state_after_update, delete_directive)
      assert get_in(state_after_delete.agent.state, [:config, :mode]) == nil

      # Test :reset operation
      reset_directive = %StateModification{
        op: :reset,
        path: [:config]
      }

      {:ok, state_after_reset} = Directive.execute(state_after_delete, reset_directive)
      assert get_in(state_after_reset.agent.state, [:config]) == nil
    end

    test "state_modification validates operation type", %{state: state} do
      directive = %StateModification{
        op: :invalid_op,
        path: [:config],
        value: :something
      }

      {:error, error} = Directive.execute(state, directive)

      assert_error_match(
        error,
        Error.validation_error("Invalid state modification operation", %{op: :invalid_op})
      )
    end

    test "state_modification handles invalid paths", %{state: state} do
      directive = %StateModification{
        op: :update,
        path: [:nonexistent, :path],
        value: fn _ -> :something end
      }

      {:error, error} = Directive.execute(state, directive)

      assert_error_match(
        error,
        Error.execution_error("Failed to modify state", %{
          error: %ArgumentError{message: "could not put/update key :path on a nil value"}
        })
      )
    end
  end

  describe "error handling" do
    test "returns error for invalid directive", %{state: state} do
      {:error, error} = Directive.execute(state, :invalid_directive)

      assert_error_match(
        error,
        Error.validation_error("Invalid directive", %{directive: :invalid_directive})
      )
    end
  end
end
