defmodule Jido.Agent.Server.SignalProcessor do
  @moduledoc """
  Handles signal processing logic for the Agent Server.
  """

  alias Jido.Agent.Server.{Directive, Router, Output, State}
  alias Jido.Agent.Server.Signal, as: ServerSignal
  alias Jido.{Instruction, Signal}

  @doc """
  Processes signals in batches for better performance and backpressure control.

  Returns `{:ok, new_data, replies, status}` where status is either 
  `:more_signals` or `:queue_empty`.
  """
  @spec process_signal_batch(State.t(), pos_integer()) ::
          {:ok, State.t(), list(), :more_signals | :queue_empty} | {:error, :empty_queue}
  def process_signal_batch(data, batch_size) do
    process_signal_batch(data, batch_size, 0, [])
  end

  @doc """
  Processes a single signal from the queue.

  Returns `{:ok, new_data, replies}` or `{:error, :empty_queue}`.
  """
  @spec process_one_signal(State.t()) ::
          {:ok, State.t(), list()} | {:error, :empty_queue}
  def process_one_signal(data) do
    case State.dequeue(data) do
      {:ok, signal, new_data} ->
        # Get any stored reply reference before processing
        reply_ref = State.get_reply_ref(new_data, signal.id)

        # Use the signal processing logic
        case process_signal_for_state_machine(new_data, signal) do
          {:ok, final_data, result} ->
            # Remove the reply ref and prepare response
            final_data = State.remove_reply_ref(final_data, signal.id)

            replies =
              case reply_ref do
                nil -> []
                from -> [{from, {:ok, result}}]
              end

            {:ok, final_data, replies}

          {:error, reason} ->
            # Remove the reply ref and prepare error response
            final_data = State.remove_reply_ref(new_data, signal.id)

            replies =
              case reply_ref do
                nil -> []
                from -> [{from, {:error, reason}}]
              end

            {:ok, final_data, replies}
        end

      {:error, :empty_queue} ->
        {:error, :empty_queue}
    end
  end

  @doc """
  Processes a signal for the GenStateMachine implementation.
  """
  @spec process_signal_for_state_machine(State.t(), Signal.t()) ::
          {:ok, State.t(), any()} | {:error, any()}
  def process_signal_for_state_machine(state, signal) do
    with state <- set_current_signal(state, signal),
         {:ok, state, result} <- execute_signal_for_state_machine(state, signal) do
      {:ok, state, result}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Executes a signal using the appropriate handler based on signal type.
  """
  @spec execute_signal_for_state_machine(State.t(), Signal.t()) ::
          {:ok, State.t(), any()} | {:error, any()}
  def execute_signal_for_state_machine(state, signal) do
    case signal.type do
      "instruction" ->
        execute_instruction_signal(state, signal)

      cmd_type when cmd_type in ["cmd.state", "cmd.queue_size"] ->
        execute_command_signal(state, signal)

      "event." <> _ ->
        execute_event_signal(state, signal)

      _ ->
        # Route the signal through the router
        case Router.route(state, signal) do
          {:ok, instructions} when is_list(instructions) ->
            execute_routed_instructions(state, instructions, signal)

          {:error, reason} ->
            {:error, reason}
        end
    end
  rescue
    error ->
      {:error, error}
  end

  @doc """
  Executes instruction signals by running them through the agent's cmd system.
  """
  @spec execute_instruction_signal(State.t(), Signal.t()) ::
          {:ok, State.t(), any()} | {:error, any()}
  def execute_instruction_signal(state, signal) do
    case signal.data do
      %Instruction{} = instruction ->
        # Execute the instruction using the agent's cmd system
        opts = [apply_directives?: false, log_level: state.log_level]

        case state.agent.__struct__.cmd(state.agent, [instruction], %{}, opts) do
          {:ok, new_agent, directives} ->
            updated_state = %{state | agent: new_agent}

            # Handle directives if any
            case handle_agent_directives(updated_state, directives) do
              {:ok, final_state} ->
                # Emit output signal
                :instruction_result
                |> ServerSignal.out_signal(final_state, new_agent.result)
                |> Output.emit(final_state)

                {:ok, final_state, new_agent.result}

              {:error, reason} ->
                {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:error, :invalid_instruction_data}
    end
  end

  @doc """
  Executes command signals (state queries, queue size, etc.).
  """
  @spec execute_command_signal(State.t(), Signal.t()) ::
          {:ok, State.t(), any()} | {:error, any()}
  def execute_command_signal(state, signal) do
    case signal.type do
      "cmd.state" ->
        {:ok, state, state}

      "cmd.queue_size" ->
        queue_size = :queue.len(state.pending_signals)
        {:ok, state, %{queue_size: queue_size}}

      _ ->
        {:error, :unknown_command}
    end
  end

  @doc """
  Executes event signals (typically just logged/emitted).
  """
  @spec execute_event_signal(State.t(), Signal.t()) ::
          {:ok, State.t(), any()} | {:error, any()}
  def execute_event_signal(state, signal) do
    # Events are typically just logged/emitted, not executed
    Output.emit(signal, state)
    {:ok, state, %{event_processed: signal.type}}
  end

  @doc """
  Executes routed instructions from the router.
  """
  @spec execute_routed_instructions(State.t(), [Instruction.t()], Signal.t()) ::
          {:ok, State.t(), any()} | {:error, any()}
  def execute_routed_instructions(state, instructions, _original_signal) do
    # Execute all routed instructions using the agent's cmd system
    opts = [apply_directives?: false, log_level: state.log_level]

    case state.agent.__struct__.cmd(state.agent, instructions, %{}, opts) do
      {:ok, new_agent, directives} ->
        updated_state = %{state | agent: new_agent}

        # Handle directives if any
        case handle_agent_directives(updated_state, directives) do
          {:ok, final_state} ->
            # Emit output signal
            :instruction_result
            |> ServerSignal.out_signal(final_state, new_agent.result)
            |> Output.emit(final_state)

            {:ok, final_state, new_agent.result}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_signal_batch(data, batch_size, processed, replies) when processed >= batch_size do
    queue_size = :queue.len(data.pending_signals)
    status = if queue_size > 0, do: :more_signals, else: :queue_empty
    {:ok, data, Enum.reverse(replies), status}
  end

  defp process_signal_batch(data, batch_size, processed, replies) do
    case process_one_signal(data) do
      {:ok, new_data, new_replies} ->
        all_replies = new_replies ++ replies

        case :queue.len(new_data.pending_signals) do
          0 ->
            # Queue is empty, return all replies
            {:ok, new_data, Enum.reverse(all_replies), :queue_empty}

          _ when new_data.mode == :step ->
            # In step mode, process only one signal
            {:ok, new_data, Enum.reverse(all_replies), :more_signals}

          _ ->
            # Continue processing in batch
            process_signal_batch(new_data, batch_size, processed + 1, all_replies)
        end

      {:error, :empty_queue} ->
        if processed > 0 do
          {:ok, data, Enum.reverse(replies), :queue_empty}
        else
          {:error, :empty_queue}
        end
    end
  end

  defp handle_agent_directives(state, directives) do
    case Directive.handle(state, directives) do
      {:ok, updated_state} ->
        {:ok, updated_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp set_current_signal(state, signal) do
    %{state | current_signal: signal}
  end
end
