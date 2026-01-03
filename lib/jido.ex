defmodule Jido do
  use Supervisor

  @moduledoc """
  自動 (Jido) - A foundational framework for building autonomous, distributed agent systems in Elixir.

  ## Architecture

  Jido uses **instance-scoped supervisors** instead of global singletons. Each Jido instance
  manages its own Registry, TaskSupervisor, and AgentSupervisor, providing complete isolation
  between different parts of your application.

  ## Getting Started

  Define a Jido instance module in your application:

      defmodule MyApp.Jido do
        use Jido, otp_app: :my_app
      end

  Configure it in your `config/config.exs`:

      config :my_app, MyApp.Jido,
        max_tasks: 1000,
        agent_pools: []

  Add it to your application's supervision tree:

      # In your application.ex
      children = [
        MyApp.Jido
      ]

  Then use the instance to manage agents:

      # Start an agent
      {:ok, pid} = MyApp.Jido.start_agent(MyAgent, id: "agent-1")

      # Look up an agent by ID
      pid = MyApp.Jido.whereis("agent-1")

      # List all agents
      agents = MyApp.Jido.list_agents()

      # Stop an agent
      :ok = MyApp.Jido.stop_agent("agent-1")

  ## Test Isolation

  For tests, use `JidoTest.Case` which automatically creates an isolated Jido instance:

      defmodule MyAgentTest do
        use JidoTest.Case, async: true

        test "my agent works", %{jido: jido} do
          {:ok, pid} = Jido.start_agent(jido, MyAgent)
          # Test in isolation...
        end
      end

  ## Core Concepts

  Jido is built around a purely functional Agent design:

  - **Agent** - An immutable data structure that holds state and can be updated via commands
  - **Actions** - Pure functions that transform agent state
  - **Directives** - Descriptions of external effects (emit signals, spawn processes, etc.)
  - **Strategies** - Pluggable execution patterns for actions

  ## Agent API

  The core operation is `cmd/2`:

      {agent, directives} = MyAgent.cmd(agent, MyAction)
      {agent, directives} = MyAgent.cmd(agent, {MyAction, %{value: 42}})
      {agent, directives} = MyAgent.cmd(agent, [Action1, Action2])

  Key invariants:
  - The returned `agent` is always complete — no "apply directives" step needed
  - `directives` are external effects only — they never modify agent state
  - `cmd/2` is a pure function — given same inputs, always same outputs

  ## Defining Agents

      defmodule MyAgent do
        use Jido.Agent,
          name: "my_agent",
          description: "My custom agent",
          schema: [
            status: [type: :atom, default: :idle],
            counter: [type: :integer, default: 0]
          ]
      end

  ## Instance Module API

  When you define an instance module with `use Jido, otp_app: :my_app`, the following
  functions are generated:

  - `child_spec/1` - Returns a supervisor child spec
  - `start_link/1` - Starts the Jido instance supervisor
  - `config/1` - Returns the runtime configuration
  - `start_agent/2` - Starts an agent under this instance
  - `stop_agent/1` - Stops an agent by pid or id
  - `whereis/1` - Looks up an agent by ID
  - `list_agents/0` - Lists all agents
  - `agent_count/0` - Returns the count of running agents
  """

  @doc """
  Defines a Jido instance module.

  ## Options

    - `:otp_app` - Required. The OTP application that holds the configuration.

  ## Example

      defmodule MyApp.Jido do
        use Jido, otp_app: :my_app
      end

  Then configure in `config/config.exs`:

      config :my_app, MyApp.Jido,
        max_tasks: 2000,
        agent_pools: []

  And add to your supervision tree:

      children = [
        MyApp.Jido
      ]

  """
  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)

    quote location: :keep do
      @otp_app unquote(otp_app)

      @doc false
      def child_spec(init_arg \\ []) do
        opts =
          config(init_arg)
          |> Keyword.put_new(:name, __MODULE__)

        Jido.child_spec(opts)
      end

      @doc false
      def start_link(init_arg \\ []) do
        opts =
          config(init_arg)
          |> Keyword.put_new(:name, __MODULE__)

        Jido.start_link(opts)
      end

      @doc """
      Returns the runtime config for this Jido instance.

      Configuration is loaded from `config :#{@otp_app}, #{inspect(__MODULE__)}` and
      overridden by any runtime options passed in.
      """
      @spec config(keyword()) :: keyword()
      def config(overrides \\ []) do
        @otp_app
        |> Application.get_env(__MODULE__, [])
        |> Keyword.merge(overrides)
      end

      defoverridable config: 1

      @doc "Starts an agent under this Jido instance."
      @spec start_agent(module() | struct(), keyword()) :: DynamicSupervisor.on_start_child()
      def start_agent(agent, opts \\ []) do
        Jido.start_agent(__MODULE__, agent, opts)
      end

      @doc "Stops an agent (by pid or id) under this Jido instance."
      @spec stop_agent(pid() | String.t()) :: :ok | {:error, :not_found}
      def stop_agent(pid_or_id) do
        Jido.stop_agent(__MODULE__, pid_or_id)
      end

      @doc "Looks up an agent by ID under this Jido instance."
      @spec whereis(String.t()) :: pid() | nil
      def whereis(id) when is_binary(id) do
        Jido.whereis(__MODULE__, id)
      end

      @doc "Lists all agents under this Jido instance."
      @spec list_agents() :: [{String.t(), pid()}]
      def list_agents do
        Jido.list_agents(__MODULE__)
      end

      @doc "Returns the count of running agents under this Jido instance."
      @spec agent_count() :: non_neg_integer()
      def agent_count do
        Jido.agent_count(__MODULE__)
      end

      @doc "Returns the Registry name for this Jido instance."
      @spec registry_name() :: atom()
      def registry_name, do: Jido.registry_name(__MODULE__)

      @doc "Returns the AgentSupervisor name for this Jido instance."
      @spec agent_supervisor_name() :: atom()
      def agent_supervisor_name, do: Jido.agent_supervisor_name(__MODULE__)

      @doc "Returns the TaskSupervisor name for this Jido instance."
      @spec task_supervisor_name() :: atom()
      def task_supervisor_name, do: Jido.task_supervisor_name(__MODULE__)
    end
  end

  @type agent_id :: String.t() | atom()

  @doc """
  Starts a Jido instance supervisor.

  ## Options
    - `:name` - Required. The name of this Jido instance (e.g., `MyApp.Jido`)

  ## Example

      {:ok, pid} = Jido.start_link(name: MyApp.Jido)
  """
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @doc false
  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)

    %{
      id: name,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: 10_000
    }
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)

    base_children = [
      {Task.Supervisor,
       name: task_supervisor_name(name), max_children: Keyword.get(opts, :max_tasks, 1000)},
      {Registry, keys: :unique, name: registry_name(name)},
      {DynamicSupervisor,
       name: agent_supervisor_name(name),
       strategy: :one_for_one,
       max_restarts: 1000,
       max_seconds: 5}
    ]

    pool_children =
      Jido.AgentPool.build_pool_child_specs(name, Keyword.get(opts, :agent_pools, []))

    Supervisor.init(base_children ++ pool_children, strategy: :one_for_one)
  end

  @doc """
  Generate a unique identifier.

  Delegates to `Jido.Util.generate_id/0`.
  """
  defdelegate generate_id(), to: Jido.Util

  @doc "Returns the Registry name for a Jido instance."
  @spec registry_name(atom()) :: atom()
  def registry_name(name), do: Module.concat(name, Registry)

  @doc "Returns the AgentSupervisor name for a Jido instance."
  @spec agent_supervisor_name(atom()) :: atom()
  def agent_supervisor_name(name), do: Module.concat(name, AgentSupervisor)

  @doc "Returns the TaskSupervisor name for a Jido instance."
  @spec task_supervisor_name(atom()) :: atom()
  def task_supervisor_name(name), do: Module.concat(name, TaskSupervisor)

  @doc "Returns the Scheduler name for a Jido instance."
  @spec scheduler_name(atom()) :: atom()
  def scheduler_name(name), do: Module.concat(name, Scheduler)

  @doc "Returns the AgentPool name for a specific pool in a Jido instance."
  @spec agent_pool_name(atom(), atom()) :: atom()
  def agent_pool_name(name, pool_name), do: Module.concat([name, AgentPool, pool_name])

  # ---------------------------------------------------------------------------
  # Agent Lifecycle
  # ---------------------------------------------------------------------------

  @doc """
  Starts an agent under a specific Jido instance.

  ## Examples

      {:ok, pid} = Jido.start_agent(MyApp.Jido, MyAgent)
      {:ok, pid} = Jido.start_agent(MyApp.Jido, MyAgent, id: "custom-id")
  """
  @spec start_agent(atom(), module() | struct(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_agent(jido_instance, agent, opts \\ []) when is_atom(jido_instance) do
    child_spec = {Jido.AgentServer, Keyword.merge(opts, agent: agent, jido: jido_instance)}
    DynamicSupervisor.start_child(agent_supervisor_name(jido_instance), child_spec)
  end

  @doc """
  Stops an agent by pid or id.

  ## Examples

      :ok = Jido.stop_agent(MyApp.Jido, pid)
      :ok = Jido.stop_agent(MyApp.Jido, "agent-id")
  """
  @spec stop_agent(atom(), pid() | String.t()) :: :ok | {:error, :not_found}
  def stop_agent(jido_instance, pid) when is_atom(jido_instance) and is_pid(pid) do
    ref = Process.monitor(pid)

    case DynamicSupervisor.terminate_child(agent_supervisor_name(jido_instance), pid) do
      :ok ->
        await_process_down(ref, pid, 5_000)
        :ok

      {:error, :not_found} = error ->
        Process.demonitor(ref, [:flush])
        error
    end
  end

  def stop_agent(jido_instance, id) when is_atom(jido_instance) and is_binary(id) do
    case whereis(jido_instance, id) do
      nil ->
        {:error, :not_found}

      pid ->
        result = stop_agent(jido_instance, pid)

        if result == :ok do
          await_registry_clear(registry_name(jido_instance), id, 1_000)
        end

        result
    end
  end

  defp await_process_down(ref, pid, timeout_ms) do
    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      timeout_ms ->
        Process.demonitor(ref, [:flush])
        :ok
    end
  end

  defp await_registry_clear(registry, id, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await_registry_clear(registry, id, deadline)
  end

  defp do_await_registry_clear(registry, id, deadline) do
    if Registry.lookup(registry, id) == [] do
      :ok
    else
      if System.monotonic_time(:millisecond) > deadline do
        :ok
      else
        Process.sleep(5)
        do_await_registry_clear(registry, id, deadline)
      end
    end
  end

  @doc """
  Looks up an agent by ID in a Jido instance's registry.

  Returns the pid if found, nil otherwise.

  ## Examples

      pid = Jido.whereis(MyApp.Jido, "agent-123")
  """
  @spec whereis(atom(), String.t()) :: pid() | nil
  def whereis(jido_instance, id) when is_atom(jido_instance) and is_binary(id) do
    case Registry.lookup(registry_name(jido_instance), id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Lists all agents running in a Jido instance.

  Returns a list of `{id, pid}` tuples.

  ## Examples

      agents = Jido.list_agents(MyApp.Jido)
      # => [{"agent-1", #PID<0.123.0>}, {"agent-2", #PID<0.124.0>}]
  """
  @spec list_agents(atom()) :: [{String.t(), pid()}]
  def list_agents(jido_instance) when is_atom(jido_instance) do
    registry_name(jido_instance)
    |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
  end

  @doc """
  Returns the count of running agents in a Jido instance.

  ## Examples

      count = Jido.agent_count(MyApp.Jido)
      # => 5
  """
  @spec agent_count(atom()) :: non_neg_integer()
  def agent_count(jido_instance) when is_atom(jido_instance) do
    agent_supervisor_name(jido_instance)
    |> DynamicSupervisor.count_children()
    |> Map.get(:active, 0)
  end

  # ---------------------------------------------------------------------------
  # Discovery
  # ---------------------------------------------------------------------------

  @doc "Lists discovered Actions with optional filtering."
  defdelegate list_actions(opts \\ []), to: Jido.Discovery

  @doc "Lists discovered Sensors with optional filtering."
  defdelegate list_sensors(opts \\ []), to: Jido.Discovery

  @doc "Lists discovered Skills with optional filtering."
  defdelegate list_skills(opts \\ []), to: Jido.Discovery

  @doc "Lists discovered Demos with optional filtering."
  defdelegate list_demos(opts \\ []), to: Jido.Discovery

  @doc "Gets an Action by its slug."
  defdelegate get_action_by_slug(slug), to: Jido.Discovery

  @doc "Gets a Sensor by its slug."
  defdelegate get_sensor_by_slug(slug), to: Jido.Discovery

  @doc "Gets a Skill by its slug."
  defdelegate get_skill_by_slug(slug), to: Jido.Discovery

  @doc "Refreshes the Discovery catalog."
  defdelegate refresh_discovery(), to: Jido.Discovery, as: :refresh

  # ---------------------------------------------------------------------------
  # Agent Coordination
  # ---------------------------------------------------------------------------

  @doc """
  Wait for an agent to reach a terminal status.

  See `Jido.Await.completion/3` for details.
  """
  defdelegate await(server, timeout_ms \\ 10_000, opts \\ []),
    to: Jido.Await,
    as: :completion

  @doc """
  Wait for a child agent to reach a terminal status.

  See `Jido.Await.child/4` for details.
  """
  defdelegate await_child(server, child_tag, timeout_ms \\ 30_000, opts \\ []),
    to: Jido.Await,
    as: :child

  @doc """
  Wait for all agents to reach terminal status.

  See `Jido.Await.all/3` for details.
  """
  defdelegate await_all(servers, timeout_ms \\ 10_000, opts \\ []),
    to: Jido.Await,
    as: :all

  @doc """
  Wait for any agent to reach terminal status.

  See `Jido.Await.any/3` for details.
  """
  defdelegate await_any(servers, timeout_ms \\ 10_000, opts \\ []),
    to: Jido.Await,
    as: :any

  @doc """
  Get the PIDs of all children of a parent agent.

  See `Jido.Await.get_children/1` for details.
  """
  defdelegate get_children(parent_server), to: Jido.Await

  @doc """
  Get a specific child's PID by tag.

  See `Jido.Await.get_child/2` for details.
  """
  defdelegate get_child(parent_server, child_tag), to: Jido.Await

  @doc """
  Check if an agent process is alive and responding.

  See `Jido.Await.alive?/1` for details.
  """
  defdelegate alive?(server), to: Jido.Await

  @doc """
  Request graceful cancellation of an agent.

  See `Jido.Await.cancel/2` for details.
  """
  defdelegate cancel(server, opts \\ []), to: Jido.Await
end
