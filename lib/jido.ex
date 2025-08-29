defmodule Jido do
  @moduledoc """
  自動 (Jido) - A foundational framework for building autonomous, distributed agent systems in Elixir.

  This module provides the main high-level API for interacting with Jido agents and components:

  ## Agent Lifecycle
  - `start_agent/2` - Start individual agents
  - `start_agents/1` - Start multiple agents at once
  - `stop_agent/2` - Gracefully stop agents
  - `restart_agent/2` - Restart agents with preserved configuration
  - `clone_agent/3` - Clone existing agents

  ## Agent Interaction
  - `call/3` - Synchronous agent communication
  - `cast/2` - Asynchronous agent communication  
  - `send_signal/4` - Send signals to agents
  - `send_instruction/4` - Send instructions to agents
  - `request/4` - High-level unified request interface

  ## Introspection & Monitoring
  - `get_agent/2` - Retrieve agent processes
  - `get_agent_state/1` - Get agent internal state
  - `get_agent_status/1` - Get agent runtime status
  - `agent_alive?/1` - Check if agent is running
  - `queue_size/1` - Check agent message queue size
  - `list_running_agents/1` - List all running agents

  ## Usage Pattern

  Applications should create their own Jido module and add it to their supervision tree:

      # lib/my_app/jido.ex
      defmodule MyApp.Jido do
        use Jido, otp_app: :my_app
      end

      # lib/my_app/application.ex  
      children = [
        MyApp.Jido,
        # ... other children
      ]

  Then interact with agents through the high-level API:

      # Start an agent
      {:ok, pid} = MyApp.Jido.start_agent(MyApp.MyAgent, id: "worker-1")

      # Send a request
      {:ok, result} = MyApp.Jido.call("worker-1", %Signal{type: "work", data: %{}})

      # Check status
      {:ok, :running} = MyApp.Jido.get_agent_status("worker-1")
  """

  @type component_metadata :: %{
          module: module(),
          name: String.t(),
          description: String.t(),
          slug: String.t(),
          category: atom() | nil,
          tags: [atom()] | nil
        }

  @type server ::
          pid() | atom() | binary() | {name :: atom() | binary(), registry :: module()}

  @type agent_id :: String.t() | atom()
  @type agent_ref :: pid() | {:ok, pid()} | agent_id()
  @type agent_status :: :idle | :running | :paused | :error | :stopping
  @type registry :: module()

  @callback config() :: keyword()

  defmacro __using__(opts) do
    quote do
      @behaviour unquote(__MODULE__)

      @otp_app unquote(opts)[:otp_app] ||
                 raise(ArgumentError, """
                 You must provide `otp_app: :your_app` to use Jido, e.g.:

                     use Jido, otp_app: :my_app
                 """)

      # Public function to retrieve config from application environment
      def config do
        Application.get_env(@otp_app, __MODULE__, [])
        |> Keyword.put_new(:agent_registry, Jido.Registry)
      end

      # Get the configured agent registry
      def agent_registry, do: config()[:agent_registry]

      # Provide a child spec so we can be placed directly under a Supervisor
      @spec child_spec(any()) :: Supervisor.child_spec()
      def child_spec(_arg) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, []},
          shutdown: 5000,
          type: :supervisor
        }
      end

      # Entry point for starting the Jido supervisor
      @spec start_link() :: Supervisor.on_start()
      def start_link do
        unquote(__MODULE__).ensure_started(__MODULE__)
      end

      # Delegate high-level API methods so they're available on MyApp.Jido
      defdelegate start_agent(agent_or_module, opts \\ []), to: Jido.Agent.Lifecycle
      defdelegate start_agents(agent_specs), to: Jido.Agent.Lifecycle
      defdelegate stop_agent(agent_ref, opts \\ []), to: Jido.Agent.Lifecycle
      defdelegate restart_agent(agent_ref, opts \\ []), to: Jido.Agent.Lifecycle
      defdelegate clone_agent(source_id, new_id, opts \\ []), to: Jido.Agent.Lifecycle

      defdelegate get_agent(id, opts \\ []), to: Jido.Agent.Lifecycle
      defdelegate get_agent!(id, opts \\ []), to: Jido.Agent.Lifecycle
      defdelegate agent_pid(agent_ref), to: Jido.Agent.Lifecycle
      defdelegate agent_alive?(agent_ref), to: Jido.Agent.Lifecycle
      defdelegate get_agent_state(agent_ref), to: Jido.Agent.Lifecycle
      defdelegate get_agent_status(agent_ref), to: Jido.Agent.Lifecycle
      defdelegate queue_size(agent_ref), to: Jido.Agent.Lifecycle
      defdelegate list_running_agents(opts \\ []), to: Jido.Agent.Lifecycle

      defdelegate call(agent_ref, message, timeout \\ 5000), to: Jido.Agent.Interaction
      defdelegate cast(agent_ref, message), to: Jido.Agent.Interaction
      defdelegate send_signal(agent_ref, type, data, opts \\ []), to: Jido.Agent.Interaction

      defdelegate send_instruction(agent_ref, action, params, opts \\ []),
        to: Jido.Agent.Interaction

      defdelegate request(agent_ref, path, payload, opts \\ []), to: Jido.Agent.Interaction

      defdelegate via(id, opts \\ []), to: Jido.Agent.Utilities
      defdelegate resolve_pid(server), to: Jido.Agent.Utilities
      defdelegate generate_id(), to: Jido.Agent.Utilities
      defdelegate log_level(agent_ref, level), to: Jido.Agent.Utilities
    end
  end

  # ============================================================================  
  # Agent Lifecycle - Direct Delegates
  # ============================================================================

  # These functions delegate to Jido.Agent.Lifecycle for backward compatibility
  # and to provide direct access to lifecycle functions
  defdelegate start_agent(agent_or_module, opts \\ []), to: Jido.Agent.Lifecycle
  defdelegate start_agents(agent_specs), to: Jido.Agent.Lifecycle
  defdelegate stop_agent(agent_ref, opts \\ []), to: Jido.Agent.Lifecycle
  defdelegate restart_agent(agent_ref, opts \\ []), to: Jido.Agent.Lifecycle
  defdelegate clone_agent(source_id, new_id, opts \\ []), to: Jido.Agent.Lifecycle

  defdelegate get_agent(id, opts \\ []), to: Jido.Agent.Lifecycle
  defdelegate get_agent!(id, opts \\ []), to: Jido.Agent.Lifecycle
  defdelegate agent_pid(agent_ref), to: Jido.Agent.Lifecycle
  defdelegate agent_alive?(agent_ref), to: Jido.Agent.Lifecycle
  defdelegate get_agent_state(agent_ref), to: Jido.Agent.Lifecycle
  defdelegate get_agent_status(agent_ref), to: Jido.Agent.Lifecycle
  defdelegate queue_size(agent_ref), to: Jido.Agent.Lifecycle
  defdelegate list_running_agents(opts \\ []), to: Jido.Agent.Lifecycle

  # Introspection & Monitoring functions have been moved to Jido.Agent.Lifecycle
  # All monitoring functions are delegated in the __using__ macro above

  # ============================================================================
  # Interaction Helpers - Delegated to Jido.Agent.Interaction
  # ============================================================================

  # These functions have been moved to Jido.Agent.Interaction
  # All interaction functions are delegated in the __using__ macro above

  # ============================================================================
  # Utility Functions - Delegated to Jido.Agent.Utilities
  # ============================================================================

  # These utility functions have been extracted to Jido.Agent.Utilities
  # All utility functions are delegated in the __using__ macro above
  defdelegate via(id, opts \\ []), to: Jido.Agent.Utilities
  defdelegate resolve_pid(server), to: Jido.Agent.Utilities
  defdelegate generate_id(), to: Jido.Agent.Utilities
  defdelegate log_level(agent_ref, level), to: Jido.Agent.Utilities

  # Agent Cloning functions have been moved to Jido.Agent.Lifecycle
  # All cloning functions are delegated in the __using__ macro above

  # ============================================================================
  # Internal Functions (Preserved from Original)
  # ============================================================================

  @doc """
  Callback used by the generated `start_link/0` function.
  This is where we actually call Jido.Supervisor.start_link.
  """
  @spec ensure_started(module()) :: Supervisor.on_start()
  def ensure_started(jido_module) do
    config = jido_module.config()
    Jido.Supervisor.start_link(jido_module, config)
  end

  # ============================================================================
  # Component Discovery (Preserved from Original)
  # ============================================================================

  # Component Discovery
  defdelegate list_actions(opts \\ []), to: Jido.Discovery
  defdelegate list_sensors(opts \\ []), to: Jido.Discovery
  defdelegate list_agents(opts \\ []), to: Jido.Discovery
  defdelegate list_skills(opts \\ []), to: Jido.Discovery
  defdelegate list_demos(opts \\ []), to: Jido.Discovery

  defdelegate get_action_by_slug(slug), to: Jido.Discovery
  defdelegate get_sensor_by_slug(slug), to: Jido.Discovery
  defdelegate get_agent_by_slug(slug), to: Jido.Discovery
  defdelegate get_skill_by_slug(slug), to: Jido.Discovery
  defdelegate get_demo_by_slug(slug), to: Jido.Discovery
end
