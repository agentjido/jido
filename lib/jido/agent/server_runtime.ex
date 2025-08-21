defmodule Jido.Agent.Server.Runtime do
  @moduledoc false
  use Private
  require Logger

  alias Jido.Error
  alias Jido.Signal
  alias Jido.Instruction
  alias Jido.Agent.Server.Callback, as: ServerCallback
  alias Jido.Agent.Server.Router, as: ServerRouter
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Agent.Server.Signal, as: ServerSignal
  alias Jido.Agent.Server.Output, as: ServerOutput
  alias Jido.Agent.Server.Directive, as: ServerDirective
  alias Jido.Agent.Directive

  @doc """
  Process all signals in the queue until empty.
  """
  @spec process_signals_in_queue(ServerState.t()) ::
          {:ok, ServerState.t()} | {:error, term()}
  def process_signals_in_queue(%ServerState{} = state) do
    case ServerState.dequeue(state) do
      {:ok, signal, new_state} ->
        # Process one signal
        case process_signal(new_state, signal) do
          {:ok, final_state, result} ->
            # If there was a reply ref, send the reply
            case ServerState.get_reply_ref(final_state, signal.id) do
              nil ->
                :ok

              from ->
                GenServer.reply(from, {:ok, result})
            end

            # Only continue processing in auto mode
            case final_state.mode do
              :auto -> process_signals_in_queue(final_state)
              :step -> {:ok, final_state}
            end

          {:error, reason} ->
            # If there was a reply ref, send the error
            case ServerState.get_reply_ref(state, signal.id) do
              nil ->
                :ok

              from ->
                GenServer.reply(from, {:error, reason})
            end

            # Only continue processing in auto mode
            case new_state.mode do
              :auto -> process_signals_in_queue(new_state)
              :step -> {:ok, new_state}
            end
        end

      {:error, :empty_queue} ->
        {:ok, state}
    end
  end

  private do
    @spec process_signal(ServerState.t(), Signal.t()) ::
            {:ok, ServerState.t(), term()} | {:error, term()}
    defp process_signal(%ServerState{} = state, %Signal{} = signal) do
      with state <- set_current_signal(state, signal),
           {:ok, state, result} <- execute_signal(state, signal) do
        case ServerState.get_reply_ref(state, signal.id) do
          nil ->
            {:ok, state, result}

          from ->
            state = ServerState.remove_reply_ref(state, signal.id)
            GenServer.reply(from, {:ok, result})
            {:ok, state, result}
        end
      else
        {:error, reason} ->
          {:error, reason}
      end
    end

    @spec execute_signal(ServerState.t(), Signal.t()) ::
            {:ok, ServerState.t(), term()} | {:error, term()}
    defp execute_signal(%ServerState{} = state, %Signal{} = signal) do
      with state <- set_current_signal(state, signal),
           {:ok, signal} <- ServerCallback.handle_signal(state, signal),
           {:ok, instructions} <- route_signal(state, signal),
           {:ok, instructions} <- apply_signal_to_first_instruction(signal, instructions),
           {:ok, opts} <- extract_opts_from_first_instruction(instructions),
           {:ok, state, result} <- do_agent_cmd(state, instructions, opts),
           {:ok, state, result} <- handle_signal_result(state, signal, result) do
        {:ok, state, result}
      else
        {:error, reason} ->
          runtime_error(state, "Error executing signal", reason, signal.id)
          {:error, reason}
      end
    end

    @dialyzer {:nowarn_function, execute_signal: 2}
    defp execute_signal(%ServerState{} = state, _invalid_signal) do
      runtime_error(state, "Invalid signal format", :invalid_signal, "invalid-signal")
      {:error, :invalid_signal}
    end

    defp do_agent_cmd(%ServerState{agent: agent} = state, instructions, opts) do
      opts = Keyword.put(opts, :apply_directives?, false)
      opts = Keyword.put(opts, :log_level, state.log_level)

      case agent.__struct__.cmd(agent, instructions, %{}, opts) do
        {:ok, new_agent, directives} ->
          state = %{state | agent: new_agent}

          case handle_agent_result(state, new_agent, directives) do
            {:ok, state} ->
              {:ok, state, new_agent.result}

            error ->
              error
          end

        {:error, reason} ->
          {:error, reason}
      end
    end

    @spec handle_agent_result(ServerState.t(), term(), [Directive.t()]) ::
            {:ok, ServerState.t()} | {:error, term()}
    defp handle_agent_result(%ServerState{} = state, agent, directives) do
      with {:ok, state} <- handle_agent_instruction_result(state, agent.result, []),
           {:ok, state} <- ServerDirective.handle(state, directives) do
        {:ok, state}
      else
        error ->
          error
      end
    end

    @spec handle_agent_instruction_result(ServerState.t(), term(), Keyword.t()) ::
            {:ok, ServerState.t()} | {:error, term()}
    defp handle_agent_instruction_result(%ServerState{} = state, result, _opts) do
      # Process the instruction result through callbacks first
      with {:ok, processed_result} <-
             ServerCallback.transform_result(state, state.current_signal, result) do
        # Use the signal's dispatch config if present, otherwise use server's default
        dispatch_config =
          case state.current_signal do
            %Signal{jido_dispatch: dispatch} when not is_nil(dispatch) ->
              dispatch

            _ ->
              state.dispatch
          end

        # Emit instruction result signal first
        opts = [
          dispatch: dispatch_config
        ]

        :instruction_result
        |> ServerSignal.out_signal(state, processed_result, opts)
        |> ServerOutput.emit(state, opts)

        # Now handle any state transitions without emitting signals
        case state.status do
          :running ->
            # Directly update the state without emitting a signal
            new_state = %{state | status: :idle}
            {:ok, new_state}

          _ ->
            {:ok, state}
        end
      end
    end

    @spec handle_signal_result(ServerState.t(), Signal.t(), term()) ::
            {:ok, ServerState.t(), term()}
    defp handle_signal_result(%ServerState{} = state, _signal, result) do
      # Process the final result through callbacks first
      with {:ok, result} <-
             ServerCallback.transform_result(state, state.current_signal, result) do
        case state.current_signal_type do
          :async ->
            # Use the signal's dispatch config if present, otherwise use server's default
            dispatch_config =
              case state.current_signal do
                %Signal{jido_dispatch: dispatch} when not is_nil(dispatch) ->
                  dispatch

                _ ->
                  state.dispatch
              end

            opts = [
              dispatch: dispatch_config
            ]

            :signal_result
            |> ServerSignal.out_signal(state, result, opts)
            |> ServerOutput.emit(state, opts)

            {:ok, state, result}

          _ ->
            # If no signal type is set, just return the result
            {:ok, state, result}
        end
      end
    end

    defp extract_opts_from_first_instruction(instructions) do
      case instructions do
        [%Instruction{opts: opts} | _] when not is_nil(opts) -> {:ok, opts}
        [%Instruction{} | _] -> {:ok, []}
        _ -> {:ok, []}
      end
    end

    defp route_signal(%ServerState{} = state, %Signal{} = signal) do
      case ServerRouter.route(state, signal) do
        {:ok, instructions} ->
          {:ok, instructions}

        {:error, reason} ->
          runtime_error(state, "Error routing signal", reason)
          {:error, reason}
      end
    end

    @dialyzer {:nowarn_function, route_signal: 2}
    defp route_signal(_state, _invalid), do: {:error, :invalid_signal}

    @dialyzer {:nowarn_function, apply_signal_to_first_instruction: 2}
    defp apply_signal_to_first_instruction(%Signal{} = signal, instructions)
         when is_list(instructions) do
      case instructions do
        [%Instruction{} = first | rest] ->
          try do
            case signal.data do
              %Instruction{} ->
                {:ok, [first | rest]}

              data when is_map(data) or is_nil(data) or is_number(data) or is_binary(data) ->
                merged_params = Map.merge(first.params || %{}, signal.data || %{})
                result = [%{first | params: merged_params} | rest]
                {:ok, result}

              _ ->
                {:ok, [first | rest]}
            end
          rescue
            error ->
              {:error, error}
          end

        [] ->
          {:ok, []}

        _ ->
          {:error, :invalid_instruction}
      end
    end

    defp runtime_error(state, message, reason, source \\ nil)

    defp runtime_error(state, message, reason, nil) do
      source =
        case state.current_signal do
          %Jido.Signal{id: id} when not is_nil(id) -> id
          _ -> "unknown"
        end

      runtime_error(state, message, reason, source)
    end

    defp runtime_error(state, message, reason, source) do
      :execution_error
      |> ServerSignal.err_signal(
        state,
        Error.execution_error(message, %{reason: reason}),
        %{source: source}
      )
      |> ServerOutput.emit(state)
    end

    defp set_current_signal(%ServerState{} = state, %Signal{} = signal) do
      %{state | current_signal: signal}
    end
  end
end
