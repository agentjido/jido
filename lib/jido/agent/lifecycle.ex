defmodule Jido.Agent.Lifecycle do
  @moduledoc """
  Agent lifecycle management for the Jido system.

  This module handles the complete lifecycle of Jido agents including:
  - Starting individual agents and agent batches
  - Stopping agents gracefully
  - Restarting agents with preserved configuration
  - Cloning existing agents
  - Agent monitoring and introspection

  All functions support multiple agent reference formats:
  - Agent PIDs (`pid()`)
  - Agent IDs (`String.t()` or `atom()`)
  - `{:ok, pid()}` tuples from other functions

  ## Agent Reference Resolution

  Functions automatically resolve agent references to PIDs using the configured
  registry. This provides a consistent interface regardless of how you identify agents.

  ## Registry Configuration

  Agent lookups use the registry configured in your Jido module. Most functions
  accept an optional `:registry` option to override the default.

  ## Error Handling

  All functions return tagged tuples for consistent error handling:
  - `{:ok, result}` for successful operations
  - `{:error, reason}` for failures

  ## Examples

      # Start an agent
      {:ok, pid} = Jido.Agent.Lifecycle.start_agent(MyApp.Agent, id: "worker-1")

      # Clone an existing agent
      {:ok, clone_pid} = Jido.Agent.Lifecycle.clone_agent("worker-1", "worker-2")

      # Restart with new configuration
      {:ok, new_pid} = Jido.Agent.Lifecycle.restart_agent("worker-1", log_level: :debug)

      # Monitor agent status
      {:ok, :running} = Jido.Agent.Lifecycle.get_agent_status("worker-1")
  """

  require Logger

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

  # ============================================================================
  # Agent Lifecycle
  # ============================================================================

  @doc """
  Starts an agent process and registers it.

  Accepts either an agent struct or an agent module/ID combination with options.
  Adds sensible defaults for registry, log level, and other configuration.

  ## Parameters

  - `agent_or_module`: Agent struct, agent module, or agent ID
  - `opts`: Keyword list of options:
    - `:id` - Agent ID (required if first param is module)
    - `:registry` - Registry to use (defaults to config)
    - `:log_level` - Log level (:debug, :info, :warn, :error)
    - `:max_queue_size` - Maximum message queue size
    - `:mode` - Agent mode (:auto, :manual)
    - `:skills` - List of skills to enable
    - Other options passed to `Jido.Agent.Server.start_link/1`

  ## Returns

  - `{:ok, pid}` - Agent started successfully
  - `{:error, reason}` - Failed to start agent

  ## Examples

      # Start with agent struct
      agent = %Jido.Agent{id: "worker-1", name: "Worker Agent"}
      {:ok, pid} = Jido.Agent.Lifecycle.start_agent(agent)

      # Start with module and options
      {:ok, pid} = Jido.Agent.Lifecycle.start_agent(MyApp.WorkerAgent, id: "worker-1")

      # Start with custom configuration
      {:ok, pid} = Jido.Agent.Lifecycle.start_agent(MyApp.WorkerAgent,
        id: "worker-1",
        log_level: :debug,
        max_queue_size: 1000
      )
  """
  @spec start_agent(struct() | module() | agent_id(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def start_agent(agent_or_module, opts \\ [])

  def start_agent(%_{} = agent, opts) do
    # Handle agent struct directly
    server_opts = build_server_opts(agent, opts)
    Jido.Agent.Server.start_link(server_opts)
  end

  def start_agent(module_or_id, opts) when is_atom(module_or_id) do
    # Check if it's a module by seeing if it exports new/2
    if Code.ensure_loaded?(module_or_id) and function_exported?(module_or_id, :new, 2) do
      # It's an agent module, create agent struct
      id = opts[:id] || generate_id()
      initial_state = opts[:initial_state] || %{}
      agent = module_or_id.new(id, initial_state)
      server_opts = build_server_opts(agent, opts)
      Jido.Agent.Server.start_link(server_opts)
    else
      # It's an atom ID, treat as ID with default behavior
      start_agent_by_id(module_or_id, opts)
    end
  end

  def start_agent(id, opts) when is_binary(id) or is_atom(id) do
    start_agent_by_id(id, opts)
  end

  @doc """
  Starts multiple agents from a list of specifications.

  Convenience helper for batch starting agents. Each spec can be:
  - `{agent_struct}` - Agent struct only
  - `{module, opts}` - Module with options
  - `{id, module, opts}` - ID, module, and options

  ## Parameters

  - `agent_specs`: List of agent specifications

  ## Returns

  - `{:ok, [pid]}` - All agents started successfully
  - `{:error, [{spec, reason}]}` - One or more agents failed to start

  ## Examples

      # Mix of different spec formats
      specs = [
        {MyApp.WorkerAgent, [id: "worker-1"]},
        {"worker-2", MyApp.WorkerAgent, [log_level: :debug]},
        {%Jido.Agent{id: "worker-3"}}
      ]

      {:ok, [pid1, pid2, pid3]} = Jido.Agent.Lifecycle.start_agents(specs)

      # Handle partial failures
      case Jido.Agent.Lifecycle.start_agents(specs) do
        {:ok, pids} -> IO.puts("All \#{length(pids)} agents started")
        {:error, failures} -> IO.puts("\#{length(failures)} agents failed")
      end
  """
  @spec start_agents([tuple()]) :: {:ok, [pid()]} | {:error, [{term(), term()}]}
  def start_agents(agent_specs) when is_list(agent_specs) do
    results =
      agent_specs
      |> Enum.map(&start_agent_from_spec/1)
      |> Enum.with_index()

    case Enum.split_with(results, fn {result, _idx} -> match?({:ok, _}, result) end) do
      {successes, []} ->
        pids = Enum.map(successes, fn {{:ok, pid}, _idx} -> pid end)
        {:ok, pids}

      {_successes, failures} ->
        failed_specs =
          Enum.map(failures, fn {{:error, reason}, idx} ->
            {Enum.at(agent_specs, idx), reason}
          end)

        {:error, failed_specs}
    end
  end

  @doc """
  Gracefully terminates a running agent.

  Stops an agent process with configurable timeout and termination reason.
  The agent will complete any in-flight operations before terminating.

  ## Parameters

  - `agent_ref`: Agent PID, ID, or `{:ok, pid}` tuple
  - `opts`: Keyword list of options:
    - `:reason` - Termination reason (default: `:normal`)
    - `:timeout` - Timeout in milliseconds (default: `5000`)

  ## Returns

  - `:ok` - Agent stopped successfully
  - `{:error, reason}` - Failed to stop agent

  ## Examples

      # Stop with default settings
      :ok = Jido.Agent.Lifecycle.stop_agent("worker-1")

      # Stop with custom reason and timeout
      :ok = Jido.Agent.Lifecycle.stop_agent("worker-1", reason: :shutdown, timeout: 10_000)

      # Stop using PID
      {:ok, pid} = Jido.get_agent("worker-1")
      :ok = Jido.Agent.Lifecycle.stop_agent(pid)

      # Pipe-friendly with get_agent result
      "worker-1" |> Jido.get_agent() |> Jido.Agent.Lifecycle.stop_agent()
  """
  @spec stop_agent(agent_ref(), keyword()) :: :ok | {:error, term()}
  def stop_agent(agent_ref, opts \\ [])

  def stop_agent({:ok, pid}, opts), do: stop_agent(pid, opts)

  def stop_agent(pid, opts) when is_pid(pid) do
    reason = opts[:reason] || :normal
    timeout = opts[:timeout] || 5000

    if Process.alive?(pid) do
      GenServer.stop(pid, reason, timeout)
    else
      :ok
    end
  rescue
    error -> {:error, error}
  end

  def stop_agent(id, opts) when is_binary(id) or is_atom(id) do
    case get_agent(id, opts) do
      {:ok, pid} -> stop_agent(pid, opts)
      {:error, :not_found} -> :ok
    end
  end

  @doc """
  Restarts an agent with its last known configuration.

  Combines stop and start operations while preserving the agent's original
  configuration. The agent will maintain the same ID and core settings.

  ## Parameters

  - `agent_ref`: Agent PID, ID, or `{:ok, pid}` tuple
  - `opts`: Keyword list of options to override:
    - `:timeout` - Stop timeout in milliseconds (default: `5000`)
    - Any other options to override in the restart

  ## Returns

  - `{:ok, pid}` - Agent restarted successfully with new PID
  - `{:error, reason}` - Failed to restart agent

  ## Examples

      # Basic restart
      {:ok, new_pid} = Jido.Agent.Lifecycle.restart_agent("worker-1")

      # Restart with custom timeout
      {:ok, new_pid} = Jido.Agent.Lifecycle.restart_agent("worker-1", timeout: 10_000)

      # Restart and override log level
      {:ok, new_pid} = Jido.Agent.Lifecycle.restart_agent("worker-1", log_level: :debug)

      # Pipe-friendly restart
      "worker-1" |> Jido.get_agent() |> Jido.Agent.Lifecycle.restart_agent()
  """
  @spec restart_agent(agent_ref(), keyword()) :: {:ok, pid()} | {:error, term()}
  def restart_agent(agent_ref, opts \\ [])

  def restart_agent({:ok, pid}, opts), do: restart_agent(pid, opts)

  def restart_agent(agent_ref, opts) do
    # Resolve to ID first for consistent behavior
    with {:ok, agent_id} <- resolve_agent_id(agent_ref),
         {:ok, pid} <- get_agent(agent_id),
         {:ok, state} <- Jido.Agent.Server.state(pid) do
      # Extract current configuration from server state
      current_opts = %{
        mode: state.mode,
        log_level: state.log_level,
        max_queue_size: state.max_queue_size,
        registry: state.registry,
        dispatch: state.dispatch,
        skills: state.skills
      }

      # Stop the agent
      stop_timeout = opts[:timeout] || 5000

      case stop_agent(pid, timeout: stop_timeout, reason: :restart) do
        :ok ->
          # Merge current options with overrides
          restart_opts =
            current_opts
            |> Map.to_list()
            |> Keyword.merge(agent: state.agent)
            |> Keyword.merge(Keyword.drop(opts, [:timeout]))

          # Start the agent with preserved + override options
          start_agent(state.agent, restart_opts)

        error ->
          error
      end
    end
  end

  @doc """
  Clones an existing agent with a new ID.

  ## Parameters

  - `source_id`: ID of the agent to clone
  - `new_id`: ID for the new cloned agent
  - `opts`: Optional keyword list of options to override for the new agent

  ## Returns

  - `{:ok, pid}` with the new agent's process ID
  - `{:error, reason}` if cloning fails

  ## Examples

      {:ok, new_pid} = Jido.Agent.Lifecycle.clone_agent("source-agent", "cloned-agent")

      # Clone with overrides
      {:ok, new_pid} = Jido.Agent.Lifecycle.clone_agent("source-agent", "cloned-agent",
        log_level: :debug,
        max_queue_size: 5000
      )
  """
  @spec clone_agent(agent_id(), agent_id(), keyword()) :: {:ok, pid()} | {:error, term()}
  def clone_agent(source_id, new_id, opts \\ []) do
    with {:ok, source_pid} <- get_agent(source_id),
         {:ok, source_state} <- Jido.Agent.Server.state(source_pid) do
      # Create new agent with updated ID but same config
      agent = %{source_state.agent | id: to_string(new_id)}

      # Merge original options with any overrides, keeping source config
      new_opts =
        source_state
        |> Map.take([
          :mode,
          :log_level,
          :max_queue_size,
          :registry,
          :dispatch,
          :skills
        ])
        |> Map.to_list()
        |> Keyword.merge([agent: agent], fn _k, _v1, v2 -> v2 end)
        |> Keyword.merge(opts, fn _k, _v1, v2 -> v2 end)

      # Ensure we have required fields from server state
      new_opts =
        new_opts
        |> Keyword.put_new(:max_queue_size, 10_000)
        |> Keyword.put_new(:mode, :auto)
        |> Keyword.put_new(:log_level, :info)
        |> Keyword.put_new(:registry, Jido.Registry)
        |> Keyword.put_new(
          :dispatch,
          {:logger, []}
        )
        |> Keyword.put_new(:skills, [])

      Jido.Agent.Server.start_link(new_opts)
    end
  end

  # ============================================================================
  # Introspection & Monitoring
  # ============================================================================

  @doc """
  Retrieves a running Agent by its ID.

  ## Parameters

  - `id`: String or atom ID of the agent to retrieve
  - `opts`: Optional keyword list of options:
    - `:registry`: Override the default agent registry

  ## Returns

  - `{:ok, pid}` if agent is found and running
  - `{:error, :not_found}` if agent doesn't exist

  ## Examples

      {:ok, agent} = Jido.Agent.Lifecycle.get_agent("my-agent")

      # Using a custom registry
      {:ok, agent} = Jido.Agent.Lifecycle.get_agent("my-agent", registry: MyApp.Registry)
  """
  @spec get_agent(agent_id(), keyword()) :: {:ok, pid()} | {:error, :not_found}
  def get_agent(id, opts \\ []) when is_binary(id) or is_atom(id) do
    registry = opts[:registry] || Jido.Registry

    case Registry.lookup(registry, id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Pipe-friendly version of get_agent that raises on errors.

  ## Parameters

  - `id`: String or atom ID of the agent to retrieve
  - `opts`: Optional keyword list of options:
    - `:registry`: Override the default agent registry

  ## Returns

  - `pid` if agent is found
  - Raises `RuntimeError` if agent not found

  ## Examples

      pid = "my-agent" |> Jido.Agent.Lifecycle.get_agent!()
  """
  @spec get_agent!(agent_id(), keyword()) :: pid()
  def get_agent!(id, opts \\ []) do
    case get_agent(id, opts) do
      {:ok, pid} -> pid
      {:error, :not_found} -> raise "Agent not found: #{id}"
    end
  end

  @doc """
  Ergonomic alias for `get_agent!/1`.

  Provides a shorter function name for retrieving agent PIDs in pipe chains.

  ## Parameters

  - `agent_ref`: Agent ID, or `{:ok, pid}` tuple to pass through

  ## Returns

  - `pid` if agent is found or if already a PID
  - Raises `RuntimeError` if agent not found

  ## Examples

      # Short alias for get_agent!
      pid = Jido.Agent.Lifecycle.agent_pid("worker-1")

      # Pass-through for existing tuples
      {:ok, pid} = Jido.Agent.Lifecycle.get_agent("worker-1")
      same_pid = Jido.Agent.Lifecycle.agent_pid({:ok, pid})
  """
  @spec agent_pid(agent_ref()) :: pid()
  def agent_pid({:ok, pid}) when is_pid(pid), do: pid
  def agent_pid(pid) when is_pid(pid), do: pid
  def agent_pid(id) when is_binary(id) or is_atom(id), do: get_agent!(id)

  @doc """
  Checks if an agent process is alive.

  Uses `Process.alive?/1` to determine if the agent process is still running.

  ## Parameters

  - `agent_ref`: Agent PID, ID, or `{:ok, pid}` tuple

  ## Returns

  - `true` if agent is alive
  - `false` if agent is not alive or not found

  ## Examples

      # Check by ID
      true = Jido.Agent.Lifecycle.agent_alive?("worker-1")

      # Check by PID
      {:ok, pid} = Jido.Agent.Lifecycle.get_agent("worker-1")
      true = Jido.Agent.Lifecycle.agent_alive?(pid)

      # Returns false for non-existent agents
      false = Jido.Agent.Lifecycle.agent_alive?("non-existent")
  """
  @spec agent_alive?(agent_ref()) :: boolean()
  def agent_alive?({:ok, pid}), do: agent_alive?(pid)

  def agent_alive?(pid) when is_pid(pid) do
    Process.alive?(pid)
  end

  def agent_alive?(id) when is_binary(id) or is_atom(id) do
    case get_agent(id) do
      {:ok, pid} -> Process.alive?(pid)
      {:error, :not_found} -> false
    end
  end

  @doc """
  Gets the current state of an agent.

  ## Parameters

  - `agent_ref`: Agent pid, ID, or return value from get_agent

  ## Returns

  - `{:ok, state}` with the agent's current state
  - `{:error, reason}` if state couldn't be retrieved

  ## Examples

      {:ok, state} = Jido.Agent.Lifecycle.get_agent_state("my-agent")
  """
  @spec get_agent_state(agent_ref()) :: {:ok, term()} | {:error, term()}
  def get_agent_state({:ok, pid}), do: get_agent_state(pid)

  def get_agent_state(pid) when is_pid(pid) do
    Jido.Agent.Server.state(pid)
  end

  def get_agent_state(id) when is_binary(id) or is_atom(id) do
    case get_agent(id) do
      {:ok, pid} -> get_agent_state(pid)
      error -> error
    end
  end

  @doc """
  Gets the current runtime status of an agent.

  Drills into the agent state to return the current status atom representing
  what the agent is currently doing.

  ## Parameters

  - `agent_ref`: Agent PID, ID, or `{:ok, pid}` tuple

  ## Returns

  - `{:ok, status}` where status is one of:
    - `:idle` - Agent is waiting for work
    - `:running` - Agent is actively processing
    - `:paused` - Agent is temporarily paused
    - `:error` - Agent encountered an error
    - `:stopping` - Agent is in the process of stopping
  - `{:error, reason}` if status couldn't be retrieved

  ## Examples

      # Check agent status
      {:ok, :running} = Jido.Agent.Lifecycle.get_agent_status("worker-1")

      # Handle different statuses
      case Jido.Agent.Lifecycle.get_agent_status("worker-1") do
        {:ok, :idle} -> IO.puts("Agent is ready for work")
        {:ok, :running} -> IO.puts("Agent is busy")
        {:ok, :error} -> IO.puts("Agent needs attention")
        {:error, reason} -> IO.puts("Can't check status: \#{reason}")
      end
  """
  @spec get_agent_status(agent_ref()) :: {:ok, agent_status()} | {:error, term()}
  def get_agent_status({:ok, pid}), do: get_agent_status(pid)

  def get_agent_status(pid) when is_pid(pid) do
    case get_agent_state(pid) do
      {:ok, state} -> {:ok, state.status}
      error -> error
    end
  end

  def get_agent_status(id) when is_binary(id) or is_atom(id) do
    case get_agent(id) do
      {:ok, pid} -> get_agent_status(pid)
      error -> error
    end
  end

  @doc """
  Gets the current message queue size for an agent.

  Uses a server command signal to retrieve the current number of pending
  messages in the agent's mailbox.

  ## Parameters

  - `agent_ref`: Agent PID, ID, or `{:ok, pid}` tuple

  ## Returns

  - `{:ok, integer}` - Current queue size
  - `{:error, reason}` - Failed to retrieve queue size

  ## Examples

      # Check queue size
      {:ok, 5} = Jido.Agent.Lifecycle.queue_size("worker-1")

      # Monitor queue buildup
      case Jido.Agent.Lifecycle.queue_size("worker-1") do
        {:ok, size} when size > 100 -> IO.puts("Queue getting large: \#{size}")
        {:ok, size} -> IO.puts("Queue normal: \#{size}")
        {:error, reason} -> IO.puts("Can't check queue: \#{reason}")
      end
  """
  @spec queue_size(agent_ref()) :: {:ok, non_neg_integer()} | {:error, term()}
  def queue_size({:ok, pid}), do: queue_size(pid)

  def queue_size(pid) when is_pid(pid) do
    case get_agent_state(pid) do
      {:ok, state} -> {:ok, :queue.len(state.pending_signals)}
      error -> error
    end
  end

  def queue_size(id) when is_binary(id) or is_atom(id) do
    case get_agent(id) do
      {:ok, pid} -> queue_size(pid)
      error -> error
    end
  end

  @doc """
  Lists all currently running agents in the registry.

  Enumerates the configured registry and returns a map of agent IDs to PIDs.
  Useful for dashboards, monitoring, and administrative operations.

  ## Parameters

  - `opts`: Keyword list of options:
    - `:registry` - Registry to enumerate (defaults to Jido.Registry)

  ## Returns

  - `{:ok, %{id => pid}}` - Map of agent IDs to PIDs
  - `{:error, reason}` - Failed to enumerate registry

  ## Examples

      # List all agents
      {:ok, agents} = Jido.Agent.Lifecycle.list_running_agents()

      # Count running agents
      {:ok, agents} = Jido.Agent.Lifecycle.list_running_agents()
      IO.puts("\#{map_size(agents)} agents running")

      # Check specific registry
      {:ok, agents} = Jido.Agent.Lifecycle.list_running_agents(registry: MyApp.Registry)
  """
  @spec list_running_agents(keyword()) :: {:ok, %{String.t() => pid()}} | {:error, term()}
  def list_running_agents(opts \\ []) do
    registry = opts[:registry] || Jido.Registry

    try do
      agents =
        Registry.select(registry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
        |> Map.new()

      {:ok, agents}
    rescue
      error -> {:error, error}
    end
  end

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  # Private helper for starting agents by ID only
  defp start_agent_by_id(id, opts) do
    # Ensure ID is a string
    string_id = to_string(id)
    initial_state = opts[:initial_state] || %{}

    # Check if a custom module is provided
    case opts[:module] do
      module when is_atom(module) and module != nil ->
        if Code.ensure_loaded?(module) and function_exported?(module, :new, 2) do
          agent = module.new(string_id, initial_state)
          server_opts = build_server_opts(agent, opts)
          Jido.Agent.Server.start_link(server_opts)
        else
          {:error, {:invalid_module, module}}
        end

      _ ->
        # Create basic agent struct manually
        agent = %Jido.Agent{
          id: string_id,
          name: string_id,
          description: "Basic agent",
          category: "general",
          tags: [],
          vsn: "1.0.0",
          schema: [],
          actions: [],
          dirty_state?: false,
          pending_instructions: :queue.new(),
          state: initial_state,
          result: nil
        }

        server_opts = build_server_opts(agent, opts)
        Jido.Agent.Server.start_link(server_opts)
    end
  end

  # Private helper to build server options from agent and opts
  defp build_server_opts(agent, opts) do
    # Set sensible defaults
    defaults = [
      registry: Jido.Registry,
      log_level: :info,
      mode: :auto,
      max_queue_size: 10_000,
      dispatch: {:logger, []},
      skills: []
    ]

    # Merge defaults with provided options, agent takes precedence
    opts
    |> Keyword.merge(defaults, fn _k, v1, _v2 -> v1 end)
    |> Keyword.put(:agent, agent)
  end

  # Private helper to start agent from different spec formats
  defp start_agent_from_spec({%_{} = agent}) do
    start_agent(agent)
  end

  defp start_agent_from_spec({module, opts}) when is_atom(module) and is_list(opts) do
    start_agent(module, opts)
  end

  defp start_agent_from_spec({id, module, opts})
       when (is_binary(id) or is_atom(id)) and is_atom(module) and is_list(opts) do
    start_agent(module, Keyword.put(opts, :id, id))
  end

  defp start_agent_from_spec(invalid_spec) do
    {:error, {:invalid_agent_spec, invalid_spec}}
  end

  # Private helper to resolve agent reference to ID
  defp resolve_agent_id(pid) when is_pid(pid) do
    # Look up ID from registry - this is more complex, need to search
    case Registry.keys(Jido.Registry, pid) do
      [id] -> {:ok, id}
      [] -> {:error, :not_registered}
      multiple -> {:error, {:multiple_registrations, multiple}}
    end
  end

  defp resolve_agent_id({:ok, pid}) when is_pid(pid) do
    resolve_agent_id(pid)
  end

  defp resolve_agent_id(id) when is_binary(id) or is_atom(id) do
    {:ok, to_string(id)}
  end

  # Private helper for generating IDs
  defp generate_id do
    Jido.Signal.ID.generate!()
  end
end
