defmodule BasicAgent do
  @moduledoc """
  A simple, entry-level agent for getting started with Jido.

  BasicAgent provides a clean, minimal API for building conversational agents
  while leveraging the full power of Jido.Agent.Server under the hood.

  ## Examples

      # Start an agent
      {:ok, pid} = BasicAgent.start_link(name: "my_bot")

      # Simple conversation
      {:ok, response} = BasicAgent.chat(pid, "Hello!")

      # Math and tools work automatically
      {:ok, response} = BasicAgent.chat(pid, "What's 2+2?")

      # Register new capabilities
      BasicAgent.register(pid, MyCustomAction)
  """

  use Jido.Agent,
    name: "basic_agent",
    description: "Simple entry-level agent for getting started with Jido",
    category: "Basic Agents",
    tags: ["basic", "simple", "entry-level"],
    vsn: "1.0.0",
    schema: [
      # Keep schema minimal for entry-level usage
      conversation: [type: {:list, :map}, default: []],
      turn: [type: :integer, default: 0],
      max_turns: [type: :integer, default: 10]
    ],
    actions: [
      # Include commonly useful actions by default
      BasicAgent.ResponseAction,
      Jido.Actions.Directives.RegisterAction,
      Jido.Skills.Arithmetic.Actions.Eval,
      Jido.Tools.Basic.Log,
      Jido.Tools.Basic.Noop,
      # StateManager actions (required by StateManager skill)
      Jido.Actions.StateManager.Set,
      Jido.Actions.StateManager.Get,
      Jido.Actions.StateManager.Update,
      Jido.Actions.StateManager.Delete
    ]

  require Logger

  @default_opts [
    agent: __MODULE__,
    mode: :auto,
    log_level: :info
  ]

  @default_timeout 30_000

  @default_routes [
    {"basic.chat",
     %Jido.Instruction{
       action: BasicAgent.ResponseAction,
       # params will be filled from signal data
       params: %{},
       context: %{}
     }},
    {"basic.register",
     %Jido.Instruction{
       action: Jido.Actions.Directives.RegisterAction,
       params: %{},
       context: %{}
     }}
  ]

  @impl true
  def start_link(opts) when is_list(opts) do
    # Ensure name is provided
    name = Keyword.fetch!(opts, :name)

    # Set up agent with conversation state
    initial_state = %{
      conversation: [],
      turn: 0,
      max_turns: Keyword.get(opts, :max_turns, 10)
    }

    # Set up signal routing for basic.chat and basic.register only
    # StateManager skill will handle jido.state.* signals automatically
    routes = []

    # Merge default options with routing
    server_opts =
      @default_opts
      |> Keyword.merge(opts)
      |> Keyword.put(:id, name)
      |> Keyword.put(:initial_state, initial_state)
      |> Keyword.put(:routes, routes)
      |> Keyword.put(:skills, [Jido.Skills.StateManager])

    Jido.Agent.Server.start_link(server_opts)
  end

  @doc """
  Simple chat interface supporting both strings and signals.

  ## Examples

      # String messages (most common)
      {:ok, response} = BasicAgent.chat(pid, "Hello there!")
      {:ok, response} = BasicAgent.chat(pid, "What's 5 + 3?")

      # Signal messages (advanced)
      signal = Jido.Signal.new!(%{type: "basic.chat", data: %{message: "Hi!"}})
      {:ok, response} = BasicAgent.chat(pid, signal)
  """
  @spec chat(pid() | String.t(), String.t() | Jido.Signal.t()) ::
          {:ok, String.t()} | {:error, term()}
  def chat(agent_ref, message) when is_binary(message) do
    {:ok, signal} = build_chat_signal(message)
    do_chat(agent_ref, signal)
  end

  def chat(agent_ref, %Jido.Signal{} = signal) do
    do_chat(agent_ref, signal)
  end

  defp do_chat(agent_ref, %Jido.Signal{type: type} = signal) do
    # Support all BasicAgent signals plus StateManager skill signals
    supported_patterns = ["basic.chat", "basic.register", "jido.state."]

    if Enum.any?(supported_patterns, &String.starts_with?(type, &1)) do
      with {:ok, pid} <- resolve_pid(agent_ref) do
        Jido.Agent.Server.call(pid, signal, @default_timeout)
      end
    else
      {:error,
       "Unsupported signal type: #{type}. BasicAgent supports signals starting with: #{Enum.join(supported_patterns, ", ")}"}
    end
  end

  @doc """
  Register a new action with the agent.

  ## Examples

      BasicAgent.register(pid, MyCustomAction)
  """
  @spec register(pid() | String.t(), module()) :: :ok | {:error, term()}
  def register(agent_ref, action_module) when is_atom(action_module) do
    with {:ok, pid} <- resolve_pid(agent_ref),
         {:ok, signal} <- build_register_signal(action_module) do
      case Jido.Agent.Server.call(pid, signal) do
        {:ok, _response} -> :ok
        error -> error
      end
    end
  end

  @doc """
  Get the agent's conversation memory.

  ## Examples

      {:ok, messages} = BasicAgent.memory(pid)
  """
  @spec memory(pid() | String.t()) :: {:ok, [map()]} | {:error, term()}
  def memory(agent_ref) do
    with {:ok, pid} <- resolve_pid(agent_ref),
         {:ok, state} <- Jido.Agent.Server.state(pid) do
      conversation = get_in(state.agent.state, [:conversation]) || []
      {:ok, conversation}
    end
  end

  @doc """
  Clear the agent's conversation memory.

  ## Examples

      :ok = BasicAgent.clear(pid)
  """
  @spec clear(pid() | String.t()) :: :ok | {:error, term()}
  def clear(agent_ref) do
    with {:ok, pid} <- resolve_pid(agent_ref),
         {:ok, signal} <- build_clear_signal() do
      case Jido.Agent.Server.call(pid, signal) do
        {:ok, _response} -> :ok
        error -> error
      end
    end
  end

  ## Signal Handling - Delegated to Actions via Routing

  @impl true
  def transform_result(%Jido.Signal{type: "basic.chat"}, %{response: response}, _instruction) do
    # Extract just the response string for simple API
    {:ok, response}
  end

  def transform_result(%Jido.Signal{type: "basic.chat"}, result, _instruction) do
    # Fallback for unexpected response format
    {:ok, inspect(result)}
  end

  def transform_result(%Jido.Signal{type: "basic.register"}, _result, _instruction) do
    # Action registration - no response needed
    {:ok, "Action registered successfully"}
  end

  def transform_result(%Jido.Signal{type: "jido.state.set"}, _result, _instruction) do
    # Memory clear - simple confirmation
    {:ok, "Memory cleared"}
  end

  def transform_result(%Jido.Signal{type: type}, result, _instruction)
      when type in ["jido.state.get", "jido.state.update", "jido.state.delete"] do
    # For other state operations, return the result as-is
    {:ok, result}
  end

  ## Private Implementation

  defp resolve_pid(pid) when is_pid(pid), do: {:ok, pid}

  defp resolve_pid(name) when is_binary(name) do
    # TODO: Implement name-based resolution via registry
    case Process.whereis(String.to_atom(name)) do
      nil -> {:error, {:agent_not_found, name}}
      pid -> {:ok, pid}
    end
  end

  defp build_chat_signal(message) do
    Jido.Signal.new(%{
      type: "basic.chat",
      data: %{message: message}
    })
  end

  defp build_register_signal(action_module) do
    Jido.Signal.new(%{
      type: "basic.register",
      data: %{action_module: action_module}
    })
  end

  defp build_clear_signal do
    Jido.Signal.new(%{
      type: "jido.state.set",
      data: %{path: [:conversation], value: []}
    })
  end
end
