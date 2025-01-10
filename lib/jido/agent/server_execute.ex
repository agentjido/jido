defmodule Jido.Agent.Server.Execute do
  @moduledoc false
  # Handles execution of signals in the agent server.

  # This module is responsible for:
  # - Processing incoming signals by enqueuing them
  # - Managing the signal queue and execution flow
  # - Handling signal execution results and state transitions
  # - Emitting events for signal processing lifecycle

  use Private
  use ExDbug, enabled: true

  alias Jido.Error
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Agent.Server.PubSub
  alias Jido.Agent.Server.Signal, as: ServerSignal
  alias Jido.Signal

  @type signal_result ::
          {:ok, ServerState.t()}
          | {:ignore, term()}
          | {:error, term()}

  @doc """
  Processes a signal by enqueuing it and starting queue processing.

  ## Parameters
    - state: The current ServerState struct containing agent state and signal queue
    - signal: The Signal struct to be processed

  ## Returns
    - `{:ok, state}` - Signal processed successfully with updated state
    - `{:error, reason}` - Signal processing failed

  ## Examples

      iex> state = %ServerState{...}
      iex> signal = %Signal{type: :action, data: %{...}}
      iex> {:ok, new_state} = Execute.process_signal(state, signal)

  """
  @spec process_signal(ServerState.t(), Signal.t()) ::
          {:ok, ServerState.t()}
          | {:error, term()}
  def process_signal(%ServerState{} = state, %Signal{} = signal) do
    case ServerState.enqueue(state, signal) do
      {:ok, new_state} ->
        process_signal_queue(new_state)

      {:error, reason} ->
        {:error, reason}
    end
  end

  private do
    # Processes the signal queue by executing signals one at a time until the queue is empty.
    #
    # Emits events for queue processing start, completion, and failure states.
    #
    # ## Parameters
    #   - state: The current ServerState struct containing the signal queue
    #
    # ## Returns
    #   - `{:ok, state}` - Queue processed successfully with updated state
    #   - `{:error, reason}` - Queue processing failed
    #
    # ## Events Emitted
    #   - queue_processing_started - When queue processing begins
    #   - queue_processing_completed - When all signals processed successfully
    #   - queue_processing_failed - If queue processing fails
    defp process_signal_queue(%ServerState{} = state) do
      PubSub.emit_event(state, ServerSignal.queue_processing_started(), %{
        queue_size: :queue.len(state.pending_signals)
      })

      case process_queue_signals(state) do
        {:ok, final_state} ->
          PubSub.emit_event(final_state, ServerSignal.queue_processing_completed(), %{})
          {:ok, final_state}

        {:error, reason} = error ->
          PubSub.emit_event(state, ServerSignal.queue_processing_failed(), %{reason: reason})
          error
      end
    end

    # Recursively processes signals in the queue until empty.
    #
    # For each signal:
    # 1. Dequeues the next signal
    # 2. Executes it via execute_signal/2
    # 3. Emits appropriate events based on execution result
    # 4. Continues processing remaining signals
    #
    # ## Parameters
    #   - state: The current ServerState struct containing the signal queue
    #
    # ## Returns
    #   - `{:ok, state}` - All signals processed successfully
    #   - `{:error, reason}` - Signal processing failed
    #
    # ## Events Emitted
    #   - queue_step_completed - When a signal executes successfully
    #   - queue_step_ignored - When a signal is ignored
    #   - queue_step_failed - When a signal fails to execute
    defp process_queue_signals(%ServerState{} = state) do
      dbug("Processing queue signals", queue_size: :queue.len(state.pending_signals))

      case ServerState.dequeue(state) do
        {:ok, signal, new_state} ->
          case execute_signal(new_state, signal) do
            {:ok, updated_state} ->
              PubSub.emit_event(updated_state, ServerSignal.queue_step_completed(), %{
                completed_signal: signal
              })

              process_queue_signals(updated_state)

            {:ignore, reason} ->
              PubSub.emit_event(new_state, ServerSignal.queue_step_ignored(), %{
                ignored_signal: signal,
                reason: reason
              })

              process_queue_signals(new_state)

            {:error, reason} = error ->
              PubSub.emit_event(new_state, ServerSignal.queue_step_failed(), %{
                failed_signal: signal,
                reason: reason
              })

              error
          end

        {:error, :empty_queue} ->
          {:ok, state}
      end
    end

    # Executes a signal based on its type.
    #
    # This function handles the core signal execution logic by:
    # 1. Determining the signal type (agent or syscall)
    # 2. Routing to the appropriate execution handler
    # 3. Providing error handling via try/rescue
    #
    # ## Parameters
    #   - state: The current ServerState struct
    #   - signal: The Signal struct to execute
    #
    # ## Returns
    #   - `{:ok, state}` - Signal executed successfully with updated state
    #   - `{:ignore, reason}` - Signal was ignored (e.g. unknown type)
    #   - `{:error, reason}` - Signal execution failed
    #
    # ## Examples
    #     iex> execute_signal(state, agent_signal)
    #     {:ok, updated_state}
    #
    #     iex> execute_signal(state, unknown_signal)
    #     {:ignore, {:unknown_signal_type, :unknown}}
    @spec execute_signal(ServerState.t(), Signal.t()) :: signal_result()
    defp execute_signal(%ServerState{} = state, %Signal{} = signal) do
      try do
        cond do
          ServerSignal.is_agent_signal?(signal) ->
            execute_agent_signal(state, signal)

          ServerSignal.is_syscall_signal?(signal) ->
            execute_syscall_signal(state, signal)

          true ->
            {:ignore, {:unknown_signal_type, signal.type}}
        end
      rescue
        error ->
          dbug("Signal execution failed", error: Exception.format(:error, error, __STACKTRACE__))
          {:error, {:signal_execution_failed, error}}
      end
    end

    # Executes a syscall signal to manage child processes.
    #
    # This function handles two types of syscall signals:
    # - Process start: Spawns a new child process using the provided child spec
    # - Process terminate: Kills an existing child process by PID
    #
    # ## Parameters
    #   - state: The current ServerState struct
    #   - signal: The Signal struct containing the syscall details
    #
    # ## Returns
    #   - `{:ok, state}` - Syscall executed successfully with updated state
    #   - `{:error, reason}` - Syscall execution failed
    #   - `{:ignore, {:unknown_server_signal, type}}` - Unknown signal type
    #
    # ## Signal Types
    #   - `ServerSignal.process_start()` - Spawns a new child process
    #   - `ServerSignal.process_terminate()` - Terminates an existing child process
    #
    # ## Examples
    #     iex> execute_syscall_signal(state, start_signal)
    #     {:ok, updated_state}
    #
    #     iex> execute_syscall_signal(state, terminate_signal)
    #     {:ok, updated_state}
    @spec execute_syscall_signal(ServerState.t(), Signal.t()) :: signal_result()
    defp execute_syscall_signal(%ServerState{} = state, %Signal{} = _signal) do
      # dbug("Processing syscall signal", signal: signal)

      {:ok, state}
      # cond do
      #   signal.type == ServerSignal.process_start() ->
      #     dbug("Executing process start syscall", child_spec: signal.data.child_spec)

      #     case Syscall.execute(state, {:spawn, signal.data.child_spec}) do
      #       {:error, reason} ->
      #         dbug("Process start failed", error: reason)
      #         {:error, reason}

      #       {result, new_state} ->
      #         dbug("Process started successfully", result: result)
      #         {:ok, new_state}
      #     end

      #   signal.type == ServerSignal.process_terminate() ->
      #     dbug("Executing process terminate syscall", child_pid: signal.data.child_pid)

      #     case Syscall.execute(state, {:kill, signal.data.child_pid}) do
      #       {:error, reason} ->
      #         dbug("Process termination failed", reason: reason)
      #         {:error, reason}

      #       {_result, new_state} ->
      #         dbug("Process terminated successfully")
      #         {:ok, new_state}
      #     end

      #   true ->
      #     dbug("Unknown server signal", type: signal.type)
      #     {:ignore, {:unknown_server_signal, signal.type}}
      # end
    end

    # Executes an agent signal based on the server's current state.
    #
    # This function handles agent signal execution with state transitions:
    #
    # - When server is paused: Queues the signal for later processing
    # - When server is idle/running: Executes the signal with proper state transitions
    # - When server is in any other state: Returns an invalid state error
    #
    # ## Parameters
    #   - state: The current ServerState struct
    #   - signal: The Signal struct to execute
    #
    # ## Returns
    #   - `{:ok, state}` - Successfully executed or queued the signal
    #   - `{:error, {:invalid_state, status}}` - Server was in invalid state
    #
    # ## State Transitions
    #   - :paused -> No transition, signal is queued
    #   - :idle/:running -> Transitions to :running, executes signal, returns to :idle
    #   - other -> Returns error
    @spec execute_agent_signal(ServerState.t(), Signal.t()) :: signal_result()
    defp execute_agent_signal(%ServerState{status: :paused} = state, signal) do
      dbug("Agent paused, queueing signal", signal: signal)
      ServerState.enqueue(state, signal)
    end

    defp execute_agent_signal(%ServerState{status: status} = state, %Signal{} = signal)
         when status in [:idle, :running] do
      dbug("Executing agent signal in #{status} state", signal: signal)

      with {:ok, state} <- ensure_running_state(state),
           {:ok, agent_result} <- agent_signal_cmd(state, signal),
           {:ok, state} <- handle_agent_result(state, agent_result),
           {:ok, idle_state} <- ServerState.transition(state, :idle) do
        dbug("Agent signal executed successfully")
        {:ok, idle_state}
      end
    end

    defp execute_agent_signal(%ServerState{status: status}, _signal) do
      dbug("Invalid state for agent signal execution", status: status)
      {:error, {:invalid_state, status}}
    end

    # Executes an agent command signal when the server is in the running state.
    #
    # This function handles the execution of agent commands by:
    # 1. Extracting the action, parameters and options from the signal
    # 2. Calling the agent's cmd/4 function with the extracted values
    # 3. Handling any errors that occur during execution
    #
    # ## Parameters
    #   - state: The current ServerState struct, must be in :running status
    #   - signal: The Signal struct containing the command to execute
    #
    # ## Returns
    #   - `{:ok, result}` - Successfully executed the command
    #   - `{:error, error}` - An error occurred during execution
    #   - `{:error, {:invalid_state, status}}` - Server was in invalid state
    @spec agent_signal_cmd(ServerState.t(), Signal.t()) :: {:ok, map()} | {:error, term()}
    defp agent_signal_cmd(%ServerState{status: :running} = state, %Signal{} = signal) do
      {:ok, {action, params, opts}} = ServerSignal.extract_actions(signal)
      dbug("Executing agent command", action: action, params: params, opts: opts)

      try do
        state.agent.__struct__.cmd(state.agent, action, params, opts)
      rescue
        error ->
          dbug("Action execution failed",
            action: action,
            error: Exception.format(:error, error, __STACKTRACE__)
          )

          {:error, error}
      end
    end

    defp agent_signal_cmd(%ServerState{status: status}, %Signal{}) do
      dbug("Invalid state for agent command", status: status)
      {:error, {:invalid_state, status}}
    end

    # Handles the result of an agent action execution.
    #
    # This function processes the result of an agent action based on its content and state.
    # It handles several cases in priority order:
    #
    # 1. Error results - If the result contains an error, returns the error
    # 2. Syscalls - If the result contains syscalls, processes them via handle_syscalls/2
    # 3. Pending instructions - If the agent has pending instructions, processes them via handle_pending_instructions/2
    # 4. Other results - Updates the server state with the new agent state
    #
    # ## Parameters
    #   - state: The current ServerState struct
    #   - agent_result: The result map from the agent action containing:
    #     - result: The actual result data
    #     - error: Optional error information
    #     - syscalls: Optional list of syscalls to process
    #     - pending_instructions: Queue of pending instructions
    #
    # ## Returns
    #   - `{:ok, state}` - Successfully processed result and updated state
    #   - `{:error, reason}` - An error occurred during processing
    @spec handle_agent_result(ServerState.t(), map()) ::
            {:ok, ServerState.t()}
            | {:error, term()}
    defp handle_agent_result(%ServerState{} = state, %{result: result} = agent_result) do
      dbug("Handling agent result", result: result)

      cond do
        # Check if result map has error key
        match?(%{error: error} when not is_nil(error), result) ->
          error = result.error
          PubSub.emit_event(state, ServerSignal.cmd_failed(), %{result: result})
          dbug("Action resulted in error", error: error)
          {:error, error}

        # Check if result map has syscalls key
        match?(%{syscalls: syscalls} when is_list(syscalls) and length(syscalls) > 0, result) ->
          dbug("Handling syscalls from result", syscalls: result.syscalls)
          PubSub.emit_event(state, ServerSignal.cmd_success_with_syscall(), %{result: result})
          handle_syscalls(state, result.syscalls)

        # Check if agent has pending instructions
        not :queue.is_empty(agent_result.pending_instructions) ->
          dbug("Agent has pending instructions",
            pending: :queue.len(agent_result.pending_instructions)
          )

          PubSub.emit_event(state, ServerSignal.cmd_success_with_pending_instructions(), %{
            result: result
          })

          handle_pending_instructions(state, agent_result)

        # Handle other results
        true ->
          dbug("Handling other result", result: result)
          PubSub.emit_event(state, ServerSignal.cmd_success(), %{result: result})
          {:ok, %{state | agent: agent_result}}
      end
    end

    # Processes pending instructions from an agent by converting them to signals.
    #
    # This function takes pending instructions from the agent's queue, converts each one into a signal,
    # and adds those signals to the server state's pending signals queue. After successful conversion,
    # it clears the agent's pending instruction queue.
    #
    # ## Parameters
    #   - state: The current ServerState struct
    #   - agent_result: The agent struct containing pending instructions to process
    #
    # ## Returns
    #   - `{:ok, state}` - Successfully converted all instructions to signals and cleared queue
    #   - `{:error, reason}` - Failed to convert an instruction or enqueue a signal
    #
    # ## Process
    # 1. Converts instruction queue to list
    # 2. For each instruction:
    #    - Creates an action signal with the instruction's action, params and opts
    #    - Enqueues the signal in the server state
    # 3. On success, clears the agent's pending instruction queue
    # 4. On any error, halts processing and returns the error
    defp handle_pending_instructions(%ServerState{} = state, agent_result) do
      dbug("Handling pending instructions",
        pending: :queue.len(agent_result.pending_instructions)
      )

      # Convert pending instructions to signals and add to state queue
      new_state =
        agent_result.pending_instructions
        |> :queue.to_list()
        |> Enum.reduce_while({:ok, %{state | agent: agent_result}}, fn instruction,
                                                                       {:ok, acc_state} ->
          case ServerSignal.action_signal(
                 acc_state.agent.id,
                 {instruction.action, instruction.params},
                 Map.get(instruction, :opts, %{}),
                 apply_state: true
               ) do
            {:ok, signal} ->
              case ServerState.enqueue(acc_state, signal) do
                {:ok, updated_state} -> {:cont, {:ok, updated_state}}
                {:error, reason} -> {:halt, {:error, reason}}
              end

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
        end)

      # Clear pending instructions from agent after converting to signals
      case new_state do
        {:ok, updated_state} ->
          {:ok,
           %{updated_state | agent: %{updated_state.agent | pending_instructions: :queue.new()}}}

        error ->
          error
      end
    end

    # Executes a list of syscalls in sequence, halting on first error.
    #
    # This function takes a list of syscalls and executes them one by one using the Syscall module.
    # If any syscall fails, execution is halted and the error is returned. Otherwise, the updated
    # state after executing all syscalls is returned.
    #
    # ## Parameters
    #   - state: The current ServerState struct
    #   - syscalls: List of syscall structs to execute
    #
    # ## Returns
    #   - `{:ok, state}` - All syscalls executed successfully
    #   - `{:error, error}` - A syscall failed during execution
    defp handle_syscalls(%ServerState{} = state, syscalls) when is_list(syscalls) do
      dbug("Handling syscalls", syscalls: syscalls)
      {:ok, state}

      # Enum.reduce_while(syscalls, {:ok, state}, fn syscall, {:ok, acc_state} ->
      #   case Jido.Agent.Server.Syscall.execute(acc_state, syscall) do
      #     {:ok, new_state} ->
      #       {:cont, {:ok, new_state}}

      #     {:error, error} ->
      #       {:halt, {:error, error}}
      #   end
      # end)
    end

    defp handle_syscalls(_state, invalid_syscalls) do
      dbug("Invalid syscalls", syscalls: invalid_syscalls)
      {:error, Error.validation_error("Invalid syscalls", %{syscalls: invalid_syscalls})}
    end

    # Ensures the server is in a running state by transitioning from idle if needed.
    #
    # This function handles three cases:
    # - When idle: Transitions to running state
    # - When already running: Returns current state unchanged
    # - When in any other state: Returns an error
    #
    # ## Parameters
    #   - state: The current ServerState struct
    #
    # ## Returns
    #   - `{:ok, state}` - Successfully transitioned to or already in running state
    #   - `{:error, {:invalid_state, status}}` - Cannot transition from current status
    defp ensure_running_state(%ServerState{status: :idle} = state) do
      dbug("Transitioning from idle to running state")

      with {:ok, running_state} <- ServerState.transition(state, :running) do
        {:ok, running_state}
      end
    end

    defp ensure_running_state(%ServerState{status: :running} = state) do
      dbug("State already running")
      {:ok, state}
    end

    defp ensure_running_state(%ServerState{status: status}) do
      dbug("Cannot transition to running state", current_status: status)
      {:error, {:invalid_state, status}}
    end
  end
end
