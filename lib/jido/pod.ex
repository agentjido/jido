defmodule Jido.Pod do
  @moduledoc """
  Pod wrapper macro and runtime helpers.

  A pod is just a `Jido.Agent` with a canonical topology and a singleton pod
  plugin mounted under the reserved `:__pod__` state key.
  """

  alias Jido.Agent
  alias Jido.Agent.DefaultPlugins
  alias Jido.Agent.InstanceManager
  alias Jido.AgentServer
  alias Jido.AgentServer.State
  alias Jido.Observe
  alias Jido.Plugin.Instance, as: PluginInstance
  alias Jido.Pod.Plugin
  alias Jido.Pod.Topology
  alias Jido.Pod.Topology.Node
  alias Jido.RuntimeStore

  @pod_state_key Plugin.state_key_atom()
  @pod_capability Plugin.capability()

  @type node_status :: :adopted | :running | :misplaced | :stopped
  @type ensure_source :: :adopted | :running | :started

  @type node_snapshot :: %{
          node: Node.t(),
          key: term(),
          pid: pid() | nil,
          running_pid: pid() | nil,
          adopted_pid: pid() | nil,
          owner: atom() | nil,
          expected_parent: map(),
          actual_parent: map() | nil,
          adopted?: boolean(),
          status: node_status()
        }

  @type ensure_result :: %{
          pid: pid(),
          source: ensure_source(),
          owner: atom() | nil,
          parent: :pod | atom()
        }

  @type reconcile_report :: %{
          requested: [atom()],
          waves: [[atom()]],
          nodes: %{atom() => ensure_result()},
          failures: %{atom() => term()},
          completed: [atom()],
          failed: [atom()],
          pending: [atom()]
        }

  @doc false
  def expand_aliases_in_ast(ast, caller_env) do
    Macro.prewalk(ast, fn
      {:__aliases__, _, _} = alias_node -> Macro.expand(alias_node, caller_env)
      other -> other
    end)
  end

  @doc false
  def expand_and_eval_literal_option(value, caller_env) do
    case value do
      nil ->
        nil

      value when is_atom(value) or is_binary(value) or is_number(value) or is_map(value) ->
        value

      value when is_list(value) ->
        value
        |> expand_aliases_in_ast(caller_env)
        |> Code.eval_quoted([], caller_env)
        |> elem(0)

      value when is_tuple(value) ->
        value
        |> expand_aliases_in_ast(caller_env)
        |> Code.eval_quoted([], caller_env)
        |> elem(0)

      other ->
        other
    end
  end

  @doc false
  def resolve_topology!(name, raw_topology, caller_env) do
    resolved = expand_and_eval_literal_option(raw_topology, caller_env)

    case resolved do
      %Topology{} = topology ->
        case Topology.with_name(topology, name) do
          {:ok, updated} ->
            updated

          {:error, reason} ->
            raise CompileError,
              description: inspect(reason),
              file: caller_env.file,
              line: caller_env.line
        end

      topology when is_map(topology) ->
        Topology.from_nodes!(name, topology)

      other ->
        raise CompileError,
          description:
            "Invalid Jido.Pod topology for #{inspect(caller_env.module)}: expected a map or %Jido.Pod.Topology{}, got: #{inspect(other)}",
          file: caller_env.file,
          line: caller_env.line
    end
  end

  @doc false
  def split_pod_plugins!(default_plugins, caller_env) do
    pod_override =
      if is_map(default_plugins) do
        Map.take(default_plugins, [@pod_state_key])
      else
        %{}
      end

    pod_plugins = DefaultPlugins.apply_agent_overrides([Plugin], pod_override)

    if pod_plugins == [] do
      raise CompileError,
        description:
          "Jido.Pod requires a singleton pod plugin under #{@pod_state_key}. " <>
            "Replace it with `default_plugins: %{#{@pod_state_key}: YourPlugin}` instead of disabling it.",
        file: caller_env.file,
        line: caller_env.line
    end

    Enum.each(pod_plugins, &validate_pod_plugin_decl!(&1, caller_env))

    remaining_default_plugins =
      if is_map(default_plugins) do
        Map.delete(default_plugins, @pod_state_key)
      else
        default_plugins
      end

    {pod_plugins, remaining_default_plugins}
  end

  defp validate_pod_plugin_decl!(decl, caller_env) do
    mod =
      case decl do
        {module, _config} -> module
        module -> module
      end

    case Code.ensure_compiled(mod) do
      {:module, _compiled} ->
        :ok

      {:error, reason} ->
        raise CompileError,
          description: "Pod plugin #{inspect(mod)} could not be compiled: #{inspect(reason)}",
          file: caller_env.file,
          line: caller_env.line
    end

    instance =
      try do
        PluginInstance.new(decl)
      rescue
        error in [ArgumentError] ->
          raise CompileError,
            description: "Invalid pod plugin #{inspect(mod)}: #{Exception.message(error)}",
            file: caller_env.file,
            line: caller_env.line
      end

    cond do
      not instance.manifest.singleton ->
        raise CompileError,
          description: "#{inspect(mod)} must be a singleton plugin to replace the pod plugin.",
          file: caller_env.file,
          line: caller_env.line

      instance.state_key != @pod_state_key ->
        raise CompileError,
          description:
            "#{inspect(mod)} must use state_key #{@pod_state_key} to replace the pod plugin.",
          file: caller_env.file,
          line: caller_env.line

      @pod_capability not in (instance.manifest.capabilities || []) ->
        raise CompileError,
          description:
            "#{inspect(mod)} must advertise capability #{@pod_capability} to replace the pod plugin.",
          file: caller_env.file,
          line: caller_env.line

      true ->
        :ok
    end
  end

  defmacro __using__(opts) do
    name = __MODULE__.expand_and_eval_literal_option(Keyword.fetch!(opts, :name), __CALLER__)
    raw_topology = Keyword.fetch!(opts, :topology)
    topology = __MODULE__.resolve_topology!(name, raw_topology, __CALLER__)

    default_plugins =
      __MODULE__.expand_and_eval_literal_option(Keyword.get(opts, :default_plugins), __CALLER__)

    {pod_plugins, remaining_default_plugins} =
      __MODULE__.split_pod_plugins!(default_plugins, __CALLER__)

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
  def pod_plugin_instance(agent_module) when is_atom(agent_module) do
    instances =
      if function_exported?(agent_module, :plugin_instances, 0) do
        agent_module.plugin_instances()
      else
        []
      end

    case Enum.find(instances, &(&1.state_key == @pod_state_key)) do
      %PluginInstance{} = instance ->
        {:ok, instance}

      nil ->
        {:error,
         Jido.Error.validation_error(
           "#{inspect(agent_module)} is missing the reserved #{@pod_state_key} plugin instance."
         )}
    end
  end

  @doc """
  Fetches pod plugin state from an agent or server state.
  """
  @spec fetch_state(Agent.t() | State.t()) :: {:ok, map()} | {:error, term()}
  def fetch_state(%State{agent: agent}), do: fetch_state(agent)

  def fetch_state(%Agent{agent_module: agent_module, state: state}) when is_map(state) do
    with {:ok, instance} <- pod_plugin_instance(agent_module) do
      case Map.get(state, instance.state_key) do
        plugin_state when is_map(plugin_state) ->
          {:ok, plugin_state}

        other ->
          {:error,
           Jido.Error.validation_error(
             "Pod plugin state is missing or malformed.",
             details: %{state_key: instance.state_key, value: other}
           )}
      end
    end
  end

  def fetch_state(agent) do
    {:error,
     Jido.Error.validation_error(
       "Expected an agent or AgentServer state when fetching pod state.",
       details: %{agent: agent}
     )}
  end

  @doc """
  Fetches the canonical topology from a module, agent, or running pod server.
  """
  @spec fetch_topology(module() | Agent.t() | State.t() | AgentServer.server()) ::
          {:ok, Topology.t()} | {:error, term()}
  def fetch_topology(module) when is_atom(module) do
    if function_exported?(module, :topology, 0) do
      {:ok, module.topology()}
    else
      with {:ok, state} <- AgentServer.state(module) do
        fetch_topology(state)
      end
    end
  end

  def fetch_topology(%State{agent: agent}), do: fetch_topology(agent)

  def fetch_topology(%Agent{} = agent) do
    with {:ok, plugin_state} <- fetch_state(agent) do
      extract_topology(plugin_state)
    end
  end

  def fetch_topology(server) do
    with {:ok, state} <- AgentServer.state(server) do
      fetch_topology(state)
    end
  end

  @doc """
  Replaces the persisted topology snapshot in a pod agent.
  """
  @spec put_topology(Agent.t(), Topology.t()) :: {:ok, Agent.t()} | {:error, term()}
  def put_topology(%Agent{} = agent, %Topology{} = topology) do
    with {:ok, instance} <- pod_plugin_instance(agent.agent_module),
         {:ok, pod_state} <- fetch_state(agent) do
      updated_state =
        pod_state
        |> Map.put(:topology, topology)
        |> Map.put(:topology_version, topology.version)

      {:ok, %{agent | state: Map.put(agent.state, instance.state_key, updated_state)}}
    end
  end

  @doc """
  Applies a pure topology transformation to a pod agent.
  """
  @spec update_topology(
          Agent.t(),
          (Topology.t() -> Topology.t() | {:ok, Topology.t()} | {:error, term()})
        ) ::
          {:ok, Agent.t()} | {:error, term()}
  def update_topology(%Agent{} = agent, fun) when is_function(fun, 1) do
    with {:ok, topology} <- fetch_topology(agent),
         {:ok, new_topology} <- normalize_topology_update(fun.(topology)) do
      put_topology(agent, new_topology)
    end
  end

  @doc """
  Returns runtime snapshots for every node in a running pod.
  """
  @spec nodes(AgentServer.server()) :: {:ok, %{atom() => node_snapshot()}} | {:error, term()}
  def nodes(server) do
    with {:ok, state} <- AgentServer.state(server),
         {:ok, topology} <- fetch_topology(state) do
      {:ok, build_node_snapshots(state, topology)}
    end
  end

  @doc """
  Looks up a node's live process if it is currently running.
  """
  @spec lookup_node(AgentServer.server(), atom()) :: {:ok, pid()} | :error | {:error, term()}
  def lookup_node(server, name) when is_atom(name) do
    with {:ok, state} <- AgentServer.state(server),
         {:ok, topology} <- fetch_topology(state),
         {:ok, node} <- fetch_node(topology, name),
         :ok <- ensure_runtime_supported(node, name) do
      case Map.get(build_node_snapshots(state, topology), name) do
        nil -> {:error, :unknown_node}
        %{running_pid: pid} when is_pid(pid) -> {:ok, pid}
        _snapshot -> :error
      end
    end
  end

  @doc """
  Ensures a named node is running and adopted into the pod manager.
  """
  @spec ensure_node(AgentServer.server(), atom(), keyword()) :: {:ok, pid()} | {:error, term()}
  def ensure_node(server, name, opts \\ []) when is_atom(name) and is_list(opts) do
    with {:ok, state} <- AgentServer.state(server),
         {:ok, topology} <- fetch_topology(state),
         {:ok, node} <- fetch_node(topology, name),
         :ok <- ensure_runtime_supported(node, name),
         {:ok, server_pid} <- resolve_runtime_server(server, state),
         {:ok, waves} <- Topology.reconcile_waves(topology, [name]) do
      case execute_runtime_plan(server_pid, state, topology, [name], waves, opts) do
        {:ok, report} ->
          {:ok, report.nodes[name].pid}

        {:error, report} ->
          {:error, node_failure_reason_from_report(topology, name, report)}
      end
    end
  end

  @doc """
  Ensures all eager nodes are running and adopted into the pod manager.
  """
  @spec reconcile(AgentServer.server(), keyword()) ::
          {:ok, reconcile_report()} | {:error, reconcile_report()}
  def reconcile(server, opts \\ []) when is_list(opts) do
    with {:ok, state} <- AgentServer.state(server),
         {:ok, topology} <- fetch_topology(state),
         {:ok, server_pid} <- resolve_runtime_server(server, state) do
      observe_pod_operation(
        [:jido, :pod, :reconcile],
        pod_event_metadata(state),
        fn ->
          eager_node_names =
            topology.nodes
            |> Enum.filter(fn {_name, node} -> node.activation == :eager end)
            |> Enum.map(&elem(&1, 0))

          with {:ok, waves} <- Topology.reconcile_waves(topology, eager_node_names) do
            execute_runtime_plan(server_pid, state, topology, eager_node_names, waves, opts)
          end
        end,
        &reconcile_measurements/1
      )
    end
  end

  defp extract_topology(%{topology: %Topology{} = topology}), do: {:ok, topology}

  defp extract_topology(plugin_state) do
    {:error,
     Jido.Error.validation_error(
       "Pod plugin state does not contain a valid topology snapshot.",
       details: %{state: plugin_state}
     )}
  end

  defp normalize_topology_update({:ok, %Topology{} = topology}), do: {:ok, topology}
  defp normalize_topology_update(%Topology{} = topology), do: {:ok, topology}
  defp normalize_topology_update({:error, _reason} = error), do: error

  defp normalize_topology_update(other) do
    {:error,
     Jido.Error.validation_error(
       "Topology update function must return a Jido.Pod.Topology or {:ok, topology}.",
       details: %{result: other}
     )}
  end

  defp fetch_node(%Topology{} = topology, name) when is_atom(name) do
    case Topology.fetch_node(topology, name) do
      {:ok, %Node{} = node} ->
        {:ok, node}

      :error ->
        {:error, :unknown_node}
    end
  end

  defp ensure_runtime_supported(%Node{kind: :agent}, _name), do: :ok

  defp ensure_runtime_supported(%Node{kind: :pod, module: module, manager: manager}, _name)
       when is_atom(module) do
    with :ok <- ensure_pod_module(module),
         :ok <- ensure_pod_manager_module(manager, module) do
      :ok
    end
  end

  defp ensure_runtime_supported(%Node{} = node, name) do
    {:error,
     Jido.Error.validation_error(
       "Pod runtime only supports kind: :agent and kind: :pod nodes today.",
       details: %{name: name, kind: node.kind}
     )}
  end

  defp ensure_pod_module(module) when is_atom(module) do
    case Code.ensure_loaded(module) do
      {:module, _loaded} ->
        cond do
          function_exported?(module, :pod?, 0) and module.pod?() ->
            case pod_plugin_instance(module) do
              {:ok, _instance} -> :ok
              {:error, reason} -> {:error, reason}
            end

          true ->
            {:error,
             Jido.Error.validation_error(
               "Pod runtime requires kind: :pod nodes to reference a pod module.",
               details: %{module: module}
             )}
        end

      {:error, reason} ->
        {:error,
         Jido.Error.validation_error(
           "Pod runtime could not load the module for a kind: :pod node.",
           details: %{module: module, reason: reason}
         )}
    end
  end

  defp ensure_pod_manager_module(manager, module) when is_atom(manager) and is_atom(module) do
    case InstanceManager.agent_module(manager) do
      {:ok, ^module} ->
        :ok

      {:ok, actual_module} ->
        {:error,
         Jido.Error.validation_error(
           "Pod runtime requires the nested pod manager to manage the declared pod module.",
           details: %{manager: manager, module: module, actual_module: actual_module}
         )}

      {:error, :not_found} ->
        {:error,
         Jido.Error.validation_error(
           "Pod runtime could not resolve the nested pod manager.",
           details: %{manager: manager, module: module}
         )}
    end
  end

  defp build_node_snapshots(%State{} = state, %Topology{} = topology) do
    Map.new(topology.nodes, fn {name, node} ->
      {name, build_node_snapshot(state, topology, name, node)}
    end)
  end

  defp running_child_pid(manager, key) do
    try do
      case InstanceManager.lookup(manager, key) do
        {:ok, pid} -> pid
        :error -> nil
      end
    rescue
      ArgumentError -> nil
    end
  end

  defp get_managed_node(manager, key, opts) do
    try do
      InstanceManager.get(manager, key, opts)
    rescue
      error in [ArgumentError, KeyError] ->
        {:error,
         Jido.Error.validation_error(
           "Failed to acquire pod node from InstanceManager.",
           details: %{manager: manager, key: key, error: Exception.message(error)}
         )}
    end
  end

  defp execute_runtime_plan(server_pid, state, topology, requested_names, waves, opts) do
    max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online())
    timeout = Keyword.get(opts, :timeout, :timer.seconds(30))

    initial_report = %{
      requested: Enum.uniq(requested_names),
      waves: waves,
      nodes: %{},
      failures: %{},
      completed: [],
      failed: [],
      pending: List.flatten(waves)
    }

    Enum.reduce_while(Enum.with_index(waves), {:ok, initial_report}, fn {wave, wave_index},
                                                                        {:ok, report} ->
      wave_results =
        Task.async_stream(
          wave,
          fn name ->
            ensure_planned_node(server_pid, state, topology, requested_names, name, report, opts)
          end,
          ordered: true,
          max_concurrency: max_concurrency,
          timeout: timeout,
          on_timeout: :kill_task
        )
        |> Enum.zip(wave)
        |> Enum.map(fn
          {{:ok, {:ok, result}}, name} -> {:ok, name, result}
          {{:ok, {:error, reason}}, name} -> {:error, name, reason}
          {{:exit, reason}, name} -> {:error, name, {:task_exit, reason}}
        end)

      updated_report = merge_wave_results(report, wave_results, waves, wave_index)

      if updated_report.failures == %{} do
        {:cont, {:ok, updated_report}}
      else
        {:halt, {:error, updated_report}}
      end
    end)
  end

  defp ensure_planned_node(server_pid, state, topology, requested_names, name, report, opts) do
    with {:ok, node} <- fetch_node(topology, name) do
      snapshot = build_node_snapshot(state, topology, name, node)
      source = snapshot_source(snapshot)

      observe_pod_operation(
        [:jido, :pod, :node, :ensure],
        node_event_metadata(state, node, name, source, snapshot.owner),
        fn ->
          with :ok <- ensure_runtime_supported(node, name) do
            do_ensure_planned_node(
              server_pid,
              state,
              topology,
              requested_names,
              name,
              node,
              snapshot,
              report,
              opts
            )
          end
        end,
        fn
          {:ok, result} ->
            %{
              source: result.source,
              parent: result.parent
            }

          _other ->
            %{}
        end
      )
    end
  end

  defp do_ensure_planned_node(
         server_pid,
         state,
         topology,
         requested_names,
         name,
         node,
         snapshot,
         report,
         opts
       ) do
    if node.kind == :pod do
      ensure_planned_pod_node(
        server_pid,
        state,
        topology,
        requested_names,
        name,
        node,
        snapshot,
        report,
        opts
      )
    else
      ensure_planned_agent_node(
        server_pid,
        state,
        topology,
        requested_names,
        name,
        node,
        snapshot,
        report,
        opts
      )
    end
  end

  defp ensure_planned_agent_node(
         server_pid,
         state,
         topology,
         requested_names,
         name,
         node,
         snapshot,
         report,
         opts
       ) do
    case snapshot.status do
      :adopted ->
        {:ok, ensure_result(name, snapshot.running_pid, :adopted, snapshot.owner)}

      :misplaced ->
        {:error, misplaced_node_reason(name, snapshot)}

      _status ->
        initial_state = node_initial_state(requested_names, name, node, opts)
        key = node_key(state, name)

        with {:ok, parent_pid} <- resolve_parent_pid(server_pid, state, topology, name, report),
             {:ok, pid} <- get_managed_node(node.manager, key, initial_state: initial_state),
             {:ok, ^pid} <- adopt_runtime_child(parent_pid, pid, name, node.meta, state, topology) do
          {:ok, ensure_result(name, pid, snapshot_source(snapshot), snapshot.owner)}
        end
    end
  end

  defp ensure_planned_pod_node(
         server_pid,
         state,
         topology,
         requested_names,
         name,
         node,
         snapshot,
         report,
         opts
       ) do
    with :ok <- ensure_pod_recursion_safe(node, state, opts) do
      case snapshot.status do
        :adopted ->
          with {:ok, _nested_report} <-
                 reconcile_nested_pod(snapshot.running_pid, node, state, opts) do
            {:ok, ensure_result(name, snapshot.running_pid, :adopted, snapshot.owner)}
          end

        :misplaced ->
          {:error, misplaced_node_reason(name, snapshot)}

        _status ->
          initial_state = node_initial_state(requested_names, name, node, opts)
          key = node_key(state, name)

          with {:ok, parent_pid} <- resolve_parent_pid(server_pid, state, topology, name, report),
               {:ok, pid} <- get_managed_node(node.manager, key, initial_state: initial_state),
               {:ok, ^pid} <-
                 adopt_runtime_child(parent_pid, pid, name, node.meta, state, topology),
               {:ok, _nested_report} <- reconcile_nested_pod(pid, node, state, opts) do
            {:ok, ensure_result(name, pid, snapshot_source(snapshot), snapshot.owner)}
          end
      end
    end
  end

  defp resolve_parent_pid(server_pid, _state, topology, name, report) do
    case Topology.owner_of(topology, name) do
      :root ->
        {:ok, server_pid}

      {:ok, owner_name} ->
        case Map.get(report.nodes, owner_name) do
          %{pid: pid} when is_pid(pid) ->
            {:ok, pid}

          nil ->
            {:error,
             Jido.Error.validation_error(
               "Cannot ensure pod node before its logical owner is running.",
               details: %{node: name, owner: owner_name}
             )}
        end

      :error ->
        {:error, :unknown_node}
    end
  end

  defp adopt_runtime_child(parent_pid, child_pid, name, meta, state, topology) do
    case AgentServer.adopt_child(parent_pid, child_pid, name, meta) do
      {:ok, ^child_pid} = success ->
        success

      {:error, _reason} = error ->
        case build_node_snapshot(state, topology, name) do
          %{status: :adopted, running_pid: ^child_pid} ->
            {:ok, child_pid}

          _snapshot ->
            error
        end
    end
  end

  defp merge_wave_results(report, wave_results, waves, wave_index) do
    {nodes, failures, completed, failed} =
      Enum.reduce(
        wave_results,
        {report.nodes, report.failures, report.completed, report.failed},
        fn
          {:ok, name, result}, {nodes_acc, failures_acc, completed_acc, failed_acc} ->
            {
              Map.put(nodes_acc, name, result),
              failures_acc,
              append_unique(completed_acc, name),
              failed_acc
            }

          {:error, name, reason}, {nodes_acc, failures_acc, completed_acc, failed_acc} ->
            {
              nodes_acc,
              Map.put(failures_acc, name, reason),
              completed_acc,
              append_unique(failed_acc, name)
            }
        end
      )

    pending = List.flatten(Enum.drop(waves, wave_index + 1))

    %{
      report
      | nodes: nodes,
        failures: failures,
        completed: completed,
        failed: failed,
        pending: pending
    }
  end

  defp build_node_snapshot(%State{} = state, %Topology{} = topology, name, node \\ nil) do
    node =
      case node do
        %Node{} = node -> node
        _other -> topology.nodes[name]
      end

    key = node_key(state, name)
    running_pid = running_child_pid(node.manager, key)
    owner = owner_name(topology, name)
    expected_parent = expected_parent_ref(state, name, owner)
    actual_parent = actual_parent_ref(state, name)
    adopted? = parent_matches?(actual_parent, expected_parent)

    status =
      cond do
        is_pid(running_pid) and adopted? -> :adopted
        is_pid(running_pid) and is_map(actual_parent) -> :misplaced
        is_pid(running_pid) -> :running
        true -> :stopped
      end

    %{
      node: node,
      key: key,
      pid: running_pid,
      running_pid: running_pid,
      adopted_pid: if(adopted?, do: running_pid, else: nil),
      owner: owner,
      expected_parent: expected_parent,
      actual_parent: actual_parent,
      adopted?: adopted?,
      status: status
    }
  end

  defp actual_parent_ref(%State{} = state, name) when is_atom(name) do
    case RuntimeStore.fetch(state.jido, :relationships, node_id(state, name)) do
      {:ok, %{parent_id: parent_id, tag: tag}} when is_binary(parent_id) ->
        %{id: parent_id, pid: Jido.whereis(state.jido, parent_id), tag: tag}

      {:ok, _other} ->
        nil

      :error ->
        nil
    end
  end

  defp owner_name(%Topology{} = topology, name) do
    case Topology.owner_of(topology, name) do
      {:ok, owner} -> owner
      _other -> nil
    end
  end

  defp expected_parent_ref(%State{} = state, name, nil) do
    %{scope: :pod, name: nil, id: state.id, tag: name}
  end

  defp expected_parent_ref(%State{} = state, name, owner_name) when is_atom(owner_name) do
    %{scope: :node, name: owner_name, id: node_id(state, owner_name), tag: name}
  end

  defp parent_matches?(%{id: actual_id, tag: actual_tag}, %{id: expected_id, tag: expected_tag}) do
    actual_id == expected_id and actual_tag == expected_tag
  end

  defp parent_matches?(_actual_parent, _expected_parent), do: false

  defp snapshot_source(%{status: :adopted}), do: :adopted
  defp snapshot_source(%{status: :stopped}), do: :started
  defp snapshot_source(%{status: :running}), do: :running
  defp snapshot_source(%{status: :misplaced}), do: :running

  defp node_initial_state(requested_names, name, node, opts) do
    if name in requested_names do
      Keyword.get(opts, :initial_state, node.initial_state)
    else
      node.initial_state
    end
  end

  defp ensure_result(_name, pid, source, owner) when is_pid(pid) do
    %{
      pid: pid,
      source: source,
      owner: owner,
      parent: owner || :pod
    }
  end

  defp node_failure_reason_from_report(topology, name, report) do
    case Map.get(report.failures, name) do
      nil ->
        Jido.Error.validation_error(
          "Pod node could not be ensured because one or more prerequisites failed.",
          details: %{
            node: name,
            prerequisites: node_prerequisites(topology, name),
            failures: report.failures,
            pending: report.pending
          }
        )

      reason ->
        reason
    end
  end

  defp misplaced_node_reason(name, snapshot) do
    Jido.Error.validation_error(
      "Pod node is already running under a different parent.",
      details: %{
        node: name,
        expected_parent: snapshot.expected_parent,
        actual_parent: snapshot.actual_parent
      }
    )
  end

  defp pod_event_metadata(%State{} = state, extra \\ %{}) when is_map(extra) do
    Map.merge(
      %{
        pod_id: state.id,
        pod_module: state.agent_module,
        agent_id: state.id,
        agent_module: state.agent_module,
        jido_instance: state.jido
      },
      extra
    )
  end

  defp node_event_metadata(%State{} = state, %Node{} = node, name, source, owner) do
    pod_event_metadata(state, %{
      node_name: name,
      node_manager: node.manager,
      node_kind: node.kind,
      source: source,
      owner: owner
    })
  end

  defp reconcile_measurements({:ok, report}) do
    %{
      node_count: map_size(report.nodes),
      requested_count: length(report.requested),
      failure_count: 0,
      pending_count: 0,
      wave_count: length(report.waves)
    }
  end

  defp reconcile_measurements({:error, report}) do
    %{
      node_count: map_size(report.nodes),
      requested_count: length(report.requested),
      failure_count: map_size(report.failures),
      pending_count: length(report.pending),
      wave_count: length(report.waves)
    }
  end

  defp observe_pod_operation(event_prefix, metadata, fun, measurement_fun)
       when is_list(event_prefix) and is_map(metadata) and is_function(fun, 0) and
              is_function(measurement_fun, 1) do
    span_ctx = Observe.start_span(event_prefix, metadata)

    try do
      case fun.() do
        {:error, reason} = error ->
          Observe.finish_span_error(span_ctx, :error, reason, [])
          error

        result ->
          Observe.finish_span(span_ctx, measurement_fun.(result))
          result
      end
    rescue
      error ->
        Observe.finish_span_error(span_ctx, :error, error, __STACKTRACE__)
        reraise error, __STACKTRACE__
    catch
      kind, reason ->
        Observe.finish_span_error(span_ctx, kind, reason, __STACKTRACE__)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp reconcile_nested_pod(pid, %Node{module: module}, %State{} = state, opts)
       when is_pid(pid) and is_atom(module) do
    nested_opts =
      opts
      |> Keyword.take([:max_concurrency, :timeout])
      |> Keyword.put(:__pod_ancestry__, pod_ancestry(opts, state) ++ [module])

    case reconcile(pid, nested_opts) do
      {:ok, report} ->
        {:ok, report}

      {:error, report} ->
        {:error, %{stage: :nested_reconcile, pod: pid, reason: report}}
    end
  end

  defp ensure_pod_recursion_safe(%Node{module: module} = node, %State{} = state, opts)
       when is_atom(module) do
    ancestry = pod_ancestry(opts, state)

    if module in ancestry do
      {:error,
       Jido.Error.validation_error(
         "Recursive pod runtime is not supported for the current pod ancestry.",
         details: %{module: module, ancestry: ancestry, manager: node.manager}
       )}
    else
      :ok
    end
  end

  defp resolve_runtime_server(server, %State{id: id, registry: registry}) do
    if is_pid(server) and Process.alive?(server) do
      {:ok, server}
    else
      case AgentServer.whereis(registry, id) do
        pid when is_pid(pid) -> {:ok, pid}
        nil -> {:error, :not_found}
      end
    end
  end

  defp pod_ancestry(opts, %State{agent_module: agent_module}) when is_list(opts) do
    opts
    |> Keyword.get(:__pod_ancestry__, [])
    |> List.wrap()
    |> Kernel.++([agent_module])
    |> Enum.uniq()
  end

  defp node_prerequisites(%Topology{} = topology, name) do
    owner =
      case Topology.owner_of(topology, name) do
        {:ok, owner_name} -> [owner_name]
        _other -> []
      end

    owner ++ Topology.dependencies_of(topology, name)
  end

  defp append_unique(items, item) do
    if item in items, do: items, else: items ++ [item]
  end

  defp node_key(%State{} = state, name) do
    {state.agent_module, pod_key(state), name}
  end

  defp node_id(%State{} = state, name) do
    state
    |> node_key(name)
    |> key_to_id()
  end

  defp key_to_id(key) do
    digest =
      key
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.url_encode64(padding: false)

    "key_" <> digest
  end

  defp pod_key(%State{lifecycle: %{pool_key: pool_key}}) when not is_nil(pool_key), do: pool_key
  defp pod_key(%State{id: id}), do: id
end
