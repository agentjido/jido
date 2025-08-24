defmodule Jido.SimpleAgent do
  @moduledoc """
  A lightweight, runtime-configurable GenServer that implements the Strands agent loop pattern:

  receive input → reason → decide → execute tools → incorporate results → respond

  This is a simpler alternative to `Jido.Agent` focused on runtime configuration
  and clear agent loop semantics.
  """

  use GenServer
  require Logger

  alias Jido.SimpleAgent.RuleBasedReasoner

  @default_max_turns 10

  ## Public API

  @doc """
  Starts a SimpleAgent GenServer.

  ## Options

    * `:name` - Name for the agent (required)
    * `:actions` - List of action modules to register (optional)
    * `:reasoner` - Reasoner module to use (defaults to RuleBasedReasoner)
    * `:max_turns` - Maximum turns per conversation (defaults to 10)

  ## Examples

      {:ok, pid} = Jido.SimpleAgent.start_link(name: "demo_agent")
      {:ok, pid} = Jido.SimpleAgent.start_link(
        name: "math_agent",
        actions: [Jido.Skills.Arithmetic.Actions.Eval]
      )
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    _name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Sends a message to the agent and gets a response.

  Returns `{:ok, response}` on success or `{:error, reason}` on failure.
  """
  @spec call(pid(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def call(pid, message) when is_binary(message) do
    GenServer.call(pid, {:call, message})
  end

  @doc """
  Registers an action with the agent.

  The action module must implement the `Jido.Action` behavior.
  """
  @spec register_action(pid(), module()) :: :ok | {:error, term()}
  def register_action(pid, action_module) when is_atom(action_module) do
    GenServer.call(pid, {:register_action, action_module})
  end

  @doc """
  Returns the list of registered actions.
  """
  @spec list_actions(pid()) :: {:ok, [module()]}
  def list_actions(pid) do
    GenServer.call(pid, :list_actions)
  end

  @doc """
  Gets the current memory state of the agent.
  """
  @spec get_memory(pid()) :: {:ok, map()}
  def get_memory(pid) do
    GenServer.call(pid, :get_memory)
  end

  @doc """
  Clears the agent's memory.
  """
  @spec clear_memory(pid()) :: :ok
  def clear_memory(pid) do
    GenServer.call(pid, :clear_memory)
  end

  ## GenServer Callbacks

  @impl GenServer
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    actions = Keyword.get(opts, :actions, [])
    reasoner = Keyword.get(opts, :reasoner, RuleBasedReasoner)
    max_turns = Keyword.get(opts, :max_turns, @default_max_turns)

    # Validate initial actions
    case validate_and_register_actions(actions) do
      {:ok, validated_actions} ->
        state = %{
          id: generate_id(),
          name: name,
          actions: validated_actions,
          reasoner: reasoner,
          memory: %{messages: [], tool_results: %{}},
          turn: 0,
          max_turns: max_turns
        }

        {:ok, state}

      {:error, reason} ->
        {:stop, {:action_validation_failed, reason}}
    end
  end

  @impl GenServer
  def handle_call({:call, message}, _from, state) do
    Logger.debug("SimpleAgent received message: #{inspect(message)}")

    # Add user message to conversation history
    user_message = %{role: :user, content: message}
    updated_memory = add_message_to_memory(state.memory, user_message)
    state = %{state | memory: updated_memory, turn: 0}

    case execute_agent_loop(state) do
      {:ok, response, final_state} ->
        {:reply, {:ok, response}, final_state}

      {:error, reason} = error ->
        Logger.error("Agent loop failed: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call({:register_action, action_module}, _from, state) do
    case validate_and_register_actions([action_module]) do
      {:ok, [validated_action]} ->
        updated_actions = [validated_action | state.actions] |> Enum.uniq()
        {:reply, :ok, %{state | actions: updated_actions}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:list_actions, _from, state) do
    {:reply, {:ok, state.actions}, state}
  end

  @impl GenServer
  def handle_call(:get_memory, _from, state) do
    {:reply, {:ok, state.memory}, state}
  end

  @impl GenServer
  def handle_call(:clear_memory, _from, state) do
    cleared_memory = %{messages: [], tool_results: %{}}
    {:reply, :ok, %{state | memory: cleared_memory, turn: 0}}
  end

  ## Private Functions

  defp execute_agent_loop(state) do
    if state.turn >= state.max_turns do
      {:error, {:loop, :max_turns_exceeded}}
    else
      case reason_and_act(state) do
        {:respond, response, final_state} ->
          # Add assistant response to memory
          assistant_message = %{role: :assistant, content: response}
          updated_memory = add_message_to_memory(final_state.memory, assistant_message)
          final_state = %{final_state | memory: updated_memory}

          {:ok, response, final_state}

        {:continue, updated_state} ->
          execute_agent_loop(updated_state)
      end
    end
  end

  defp reason_and_act(state) do
    # Get the last user message for reasoning
    last_message = get_last_message(state.memory)

    case state.reasoner.reason(last_message, state) do
      {:respond, response} ->
        {:respond, response, state}

      {:tool_call, action_module, params} ->
        execute_tool(action_module, params, state)

      {:error, reason} ->
        Logger.error("Reasoner failed: #{inspect(reason)}")
        {:respond, "I'm sorry, I encountered an error while processing your request.", state}
    end
  end

  defp execute_tool(action_module, params, state) do
    # Validate action is registered
    if action_module in state.actions do
      # Create context with conversation memory
      context = %{memory: state.memory}

      case action_module.run(params, context) do
        {:ok, result} ->
          # Store result in tool_results
          updated_tool_results = Map.put(state.memory.tool_results, action_module, result)

          # Add tool message to conversation history
          tool_message = %{
            role: :tool,
            name: action_module,
            content: inspect(result)
          }

          updated_memory =
            %{
              state.memory
              | tool_results: updated_tool_results
            }
            |> add_message_to_memory(tool_message)

          updated_state = %{
            state
            | memory: updated_memory,
              turn: state.turn + 1
          }

          # Continue the loop to let reasoner process the tool result
          {:continue, updated_state}

        {:error, reason} ->
          Logger.error("Tool execution failed: #{inspect(reason)}")

          error_response =
            "I encountered an error while executing the #{action_module} action: #{inspect(reason)}"

          {:respond, error_response, state}
      end
    else
      error_response = "Action #{action_module} is not registered with this agent."
      {:respond, error_response, state}
    end
  end

  defp validate_and_register_actions(actions) do
    Jido.Util.validate_actions(actions)
  end

  defp add_message_to_memory(memory, message) do
    %{memory | messages: memory.messages ++ [message]}
  end

  defp get_last_message(memory) do
    case memory.messages do
      [] -> nil
      messages -> List.last(messages)
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
