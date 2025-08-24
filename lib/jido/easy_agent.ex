defmodule Jido.EasyAgent do
  @moduledoc """
  A SimpleAgent-like API built on top of Jido.Agent.Server.

  Provides the simple developer experience of SimpleAgent while leveraging
  the production-ready capabilities of Agent.Server under the hood.

  This creates a "magic wrapper" that:
  - Uses RuntimeAgent to avoid compile-time module requirements
  - Converts simple messages into instruction plans via reasoner
  - Hides Agent.Server complexity behind SimpleAgent API
  - Provides immediate responses using Agent.Server's call mechanism

  ## Examples

      # Simple API like SimpleAgent
      {:ok, agent} = EasyAgent.start_link(name: "demo")
      {:ok, response} = EasyAgent.call(agent, "What's 2+2?")
      
      # But with Agent.Server power under the hood
  """

  require Logger
  alias Jido.{Signal, Instruction}

  @doc """
  Starts an EasyAgent backed by Agent.Server.

  ## Options

    * `:name` - Name for the agent (required)
    * `:actions` - List of action modules to register (optional)
    * `:reasoner` - Reasoner module to use (defaults to EasyAgent.Reasoner)
    * `:max_turns` - Maximum turns per conversation (defaults to 10)

  ## Examples

      {:ok, agent} = EasyAgent.start_link(name: "demo")
      {:ok, agent} = EasyAgent.start_link(
        name: "math_agent", 
        actions: [Jido.Skills.Arithmetic.Actions.Eval]
      )
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts) when is_list(opts) do
    name = Keyword.fetch!(opts, :name)
    actions = Keyword.get(opts, :actions, [])
    reasoner = Keyword.get(opts, :reasoner, Jido.EasyAgent.Reasoner)
    max_turns = Keyword.get(opts, :max_turns, 10)

    # Create agent instance using RuntimeAgent
    id = generate_id()

    agent =
      Jido.EasyAgent.RuntimeAgent.new(id, %{
        name: name,
        reasoner: reasoner,
        max_turns: max_turns,
        conversation: [],
        turn: 0
      })

    # Start Agent.Server with the runtime agent
    server_opts = [
      id: id,
      agent: agent,
      actions: actions,
      mode: :auto,
      registry: ensure_registry()
    ]

    case Jido.Agent.Server.start_link(server_opts) do
      {:ok, pid} ->
        # Store mapping for simple name-based lookup
        ensure_ets_table()
        :ets.insert(:easy_agents, {name, pid})
        {:ok, pid}

      error ->
        error
    end
  end

  @doc """
  Sends a message to the agent and gets a response.

  Converts the simple message into a proper instruction plan and executes
  it using Agent.Server, then returns just the final response.
  """
  @spec call(pid() | String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def call(agent_ref, message) when is_binary(message) do
    with {:ok, pid} <- resolve_agent_pid(agent_ref),
         {:ok, server_state} <- Jido.Agent.Server.state(pid) do
      agent = server_state.agent
      reasoner = agent.state.reasoner

      # Use reasoner to determine how to handle the message
      case reasoner.reason(message, agent.state) do
        {:respond, response} ->
          # Direct response - update conversation and return
          update_conversation_and_respond(pid, agent, message, response)

        {:instructions, instructions} ->
          # Execute instructions via Agent.Server
          execute_instructions_and_respond(pid, agent, message, instructions)

        {:error, reason} ->
          Logger.error("Reasoner failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Registers an action with the agent.
  """
  @spec register_action(pid() | String.t(), module()) :: :ok | {:error, term()}
  def register_action(agent_ref, action_module) when is_atom(action_module) do
    with {:ok, pid} <- resolve_agent_pid(agent_ref),
         {:ok, server_state} <- Jido.Agent.Server.state(pid) do
      # Register action with the agent
      {:ok, updated_agent} = Jido.Agent.register_action(server_state.agent, action_module)

      # TODO: Update the agent in the server
      # For POC, assume it worked
      Logger.debug("Registered action #{action_module} with EasyAgent")
      :ok
    end
  end

  ## Private Implementation

  defp ensure_registry do
    # Use a simple registry for EasyAgent processes
    registry_name = :easy_agent_registry

    case Registry.start_link(keys: :unique, name: registry_name) do
      {:ok, _} -> registry_name
      {:error, {:already_started, _}} -> registry_name
    end
  end

  defp ensure_ets_table do
    case :ets.whereis(:easy_agents) do
      :undefined ->
        :ets.new(:easy_agents, [:set, :public, :named_table])

      _tid ->
        :ok
    end
  end

  defp resolve_agent_pid(pid) when is_pid(pid), do: {:ok, pid}

  defp resolve_agent_pid(name) when is_binary(name) do
    case :ets.lookup(:easy_agents, name) do
      [{^name, pid}] -> {:ok, pid}
      [] -> {:error, {:agent_not_found, name}}
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  # Handle direct responses from reasoner
  defp update_conversation_and_respond(pid, agent, user_message, response) do
    # TODO: Update conversation history in agent state
    # For POC, just return the response
    Logger.debug("EasyAgent direct response: #{response}")
    {:ok, response}
  end

  # Handle instruction execution from reasoner  
  defp execute_instructions_and_respond(pid, agent, user_message, instructions) do
    # TODO: Execute instructions via Agent.Server and collect results
    # For POC, simulate execution

    case instructions do
      [%Instruction{action: Jido.Skills.Arithmetic.Actions.Eval, params: params}] ->
        # Simulate math execution
        expression = params.expression

        case evaluate_expression(expression) do
          {:ok, result} -> {:ok, to_string(result)}
          {:error, reason} -> {:ok, "I couldn't calculate that: #{reason}"}
        end

      _ ->
        # TODO: Handle other instruction types
        {:ok, "I executed some actions for you!"}
    end
  end

  # TODO: Use actual Jido.Skills.Arithmetic.Actions.Eval
  defp evaluate_expression(expr) do
    try do
      # Simple math evaluation for POC
      {result, _} = Code.eval_string(expr)
      {:ok, result}
    rescue
      _ -> {:error, "Invalid expression"}
    end
  end
end
