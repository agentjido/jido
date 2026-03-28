defmodule Jido.Pod do
  @moduledoc """
  Pod wrapper macro and runtime helpers.

  A pod is just a `Jido.Agent` with a canonical topology and a singleton pod
  plugin mounted under the reserved `:__pod__` state key.
  """

  alias Jido.Agent
  alias Jido.Agent.InstanceManager
  alias Jido.AgentServer
  alias Jido.AgentServer.State
  alias Jido.Plugin.Instance, as: PluginInstance
  alias Jido.Pod.Definition
  alias Jido.Pod.Mutable
  alias Jido.Pod.Mutation
  alias Jido.Pod.Mutation.Report
  alias Jido.Pod.Runtime
  alias Jido.Pod.Topology
  alias Jido.Pod.Topology.Node
  alias Jido.Pod.TopologyState

  @type node_status :: :adopted | :running | :misplaced | :stopped
  @type ensure_source :: :adopted | :running | :started
  @type node_name :: Topology.node_name()

  @type node_snapshot :: %{
          node: Node.t(),
          key: term(),
          pid: pid() | nil,
          running_pid: pid() | nil,
          adopted_pid: pid() | nil,
          owner: node_name() | nil,
          expected_parent: map(),
          actual_parent: map() | nil,
          adopted?: boolean(),
          status: node_status()
        }

  @type ensure_result :: %{
          pid: pid(),
          source: ensure_source(),
          owner: node_name() | nil,
          parent: :pod | node_name()
        }

  @type reconcile_report :: %{
          requested: [node_name()],
          waves: [[node_name()]],
          nodes: %{node_name() => ensure_result()},
          failures: %{node_name() => term()},
          completed: [node_name()],
          failed: [node_name()],
          pending: [node_name()]
        }

  @type mutation_report :: Report.t()

  defmacro __using__(opts) do
    name = Definition.expand_and_eval_literal_option(Keyword.fetch!(opts, :name), __CALLER__)
    raw_topology = Keyword.get(opts, :topology, %{})
    topology = Definition.resolve_topology!(name, raw_topology, __CALLER__)

    default_plugins =
      Definition.expand_and_eval_literal_option(Keyword.get(opts, :default_plugins), __CALLER__)

    {pod_plugins, remaining_default_plugins} =
      Definition.split_pod_plugins!(default_plugins, __CALLER__)

    agent_opts =
      opts
      |> Keyword.delete(:topology)
      |> Keyword.put(:plugins, pod_plugins ++ Keyword.get(opts, :plugins, []))
      |> then(fn resolved_opts ->
        if is_nil(remaining_default_plugins) do
          Keyword.delete(resolved_opts, :default_plugins)
        else
          Keyword.put(resolved_opts, :default_plugins, remaining_default_plugins)
        end
      end)

    quote location: :keep do
      use Jido.Agent, unquote(Macro.escape(agent_opts))

      @pod_topology unquote(Macro.escape(topology))

      @doc "Returns the canonical topology for this pod agent."
      @spec topology() :: Jido.Pod.Topology.t()
      def topology, do: @pod_topology

      @doc "Returns true for pod-wrapped agent modules."
      @spec pod?() :: true
      def pod?, do: true
    end
  end

  @doc """
  Gets a pod instance through the given `InstanceManager` and immediately
  reconciles eager nodes.

  This is the default happy path for pod lifecycle access. Call
  `Jido.Agent.InstanceManager.get/3` directly if you need lower-level control
  over reconciliation timing.
  """
  @spec get(atom(), term(), keyword()) :: {:ok, pid()} | {:error, term()}
  def get(manager, key, opts \\ []) when is_atom(manager) and is_list(opts) do
    with {:ok, pod_pid} <- InstanceManager.get(manager, key, opts) do
      case reconcile(pod_pid) do
        {:ok, _started} ->
          {:ok, pod_pid}

        {:error, reason} ->
          {:error, %{stage: :reconcile, pod: pod_pid, reason: reason}}
      end
    end
  end

  @doc """
  Returns the reserved pod plugin instance for a pod-wrapped agent module.
  """
  @spec pod_plugin_instance(module()) :: {:ok, PluginInstance.t()} | {:error, term()}
  defdelegate pod_plugin_instance(agent_module), to: TopologyState

  @doc """
  Fetches pod plugin state from an agent or server state.
  """
  @spec fetch_state(Agent.t() | State.t()) :: {:ok, map()} | {:error, term()}
  defdelegate fetch_state(agent_or_state), to: TopologyState

  @doc """
  Fetches the canonical topology from a module, agent, or running pod server.
  """
  @spec fetch_topology(module() | Agent.t() | State.t() | AgentServer.server()) ::
          {:ok, Topology.t()} | {:error, term()}
  defdelegate fetch_topology(source), to: TopologyState

  @doc """
  Replaces the persisted topology snapshot in a pod agent.

  Structural topology changes advance `topology.version`; no-op replacements
  preserve the current version.
  """
  @spec put_topology(Agent.t(), Topology.t()) :: {:ok, Agent.t()} | {:error, term()}
  defdelegate put_topology(agent, topology), to: TopologyState

  @doc """
  Applies a pure topology transformation to a pod agent.

  Structural topology changes advance `topology.version`; no-op updates preserve
  the current version.
  """
  @spec update_topology(
          Agent.t(),
          (Topology.t() -> Topology.t() | {:ok, Topology.t()} | {:error, term()})
        ) ::
          {:ok, Agent.t()} | {:error, term()}
  defdelegate update_topology(agent, fun), to: TopologyState

  @doc """
  Applies live topology mutations to a running pod and waits for runtime work to finish.

  `server` follows the same resolution rules as `Jido.AgentServer.state/1` and
  `Jido.AgentServer.call/3`. Pass the running pod pid, a locally registered
  server name, or another resolvable runtime server reference. Raw string ids
  still require explicit registry lookup before use.
  """
  @spec mutate(AgentServer.server(), [Mutation.t() | term()], keyword()) ::
          {:ok, mutation_report()} | {:error, mutation_report() | term()}
  defdelegate mutate(server, ops, opts \\ []), to: Mutable

  @doc """
  Builds state ops and runtime effects for an in-turn pod mutation.
  """
  @spec mutation_effects(Agent.t(), [Mutation.t() | term()], keyword()) ::
          {:ok, [struct()]} | {:error, term()}
  defdelegate mutation_effects(agent, ops, opts \\ []), to: Mutable

  @doc """
  Returns runtime snapshots for every node in a running pod.
  """
  @spec nodes(AgentServer.server()) :: {:ok, %{node_name() => node_snapshot()}} | {:error, term()}
  defdelegate nodes(server), to: Runtime

  @doc """
  Looks up a node's live process if it is currently running.
  """
  @spec lookup_node(AgentServer.server(), node_name()) :: {:ok, pid()} | :error | {:error, term()}
  defdelegate lookup_node(server, name), to: Runtime

  @doc """
  Ensures a named node is running and adopted into the pod manager.
  """
  @spec ensure_node(AgentServer.server(), node_name(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  defdelegate ensure_node(server, name, opts \\ []), to: Runtime

  @doc """
  Ensures all eager nodes are running and adopted into the pod manager.
  """
  @spec reconcile(AgentServer.server(), keyword()) ::
          {:ok, reconcile_report()} | {:error, reconcile_report()}
  defdelegate reconcile(server, opts \\ []), to: Runtime

  @doc false
  @spec mark_mutation_lock(Agent.t(), map(), String.t() | nil) :: :ok
  defdelegate mark_mutation_lock(agent, context, mutation_id), to: Mutable
end
