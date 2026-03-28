defmodule Jido.Pod do
  @moduledoc """
  Pod wrapper macro and runtime helpers.

  A pod is just a `Jido.Agent` with a canonical topology and a singleton pod
  plugin mounted under the reserved `:__pod__` state key.
  """

  alias Jido.Agent
  alias Jido.Agent.DefaultPlugins
  alias Jido.Agent.InstanceManager
  alias Jido.Agent.StateOp
  alias Jido.AgentServer
  alias Jido.AgentServer.{ChildInfo, ParentRef}
  alias Jido.AgentServer.StopChildRuntime
  alias Jido.AgentServer.State
  alias Jido.Observe
  alias Jido.Plugin.Instance, as: PluginInstance
  alias Jido.Pod.Directive.ApplyMutation
  alias Jido.Pod.Mutation
  alias Jido.Pod.Mutation.{Plan, Planner, Report}
  alias Jido.Pod.Plugin
  alias Jido.Pod.Topology
  alias Jido.Pod.Topology.Node
  alias Jido.RuntimeStore
  alias Jido.Signal

  @pod_state_key Plugin.state_key_atom()
  @pod_capability Plugin.capability()
  @mutation_lock_table :jido_pod_mutation_locks
  defguardp is_node_name(name) when is_atom(name) or is_binary(name)

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

      value when is_atom(value) or is_binary(value) or is_number(value) ->
        value

      %_{} = struct ->
        struct

      {:__aliases__, _, _} = alias_node ->
        Macro.expand(alias_node, caller_env)

      value when is_list(value) ->
        Enum.map(value, fn
          {key, nested_value} ->
            {
              expand_and_eval_literal_option(key, caller_env),
              expand_and_eval_literal_option(nested_value, caller_env)
            }

          nested_value ->
            expand_and_eval_literal_option(nested_value, caller_env)
        end)

      value when is_map(value) ->
        Map.new(value, fn {key, nested_value} ->
          {
            expand_and_eval_literal_option(key, caller_env),
            expand_and_eval_literal_option(nested_value, caller_env)
          }
        end)

      value when is_tuple(value) ->
        if ast_node?(value) do
          value
          |> expand_aliases_in_ast(caller_env)
          |> Code.eval_quoted([], caller_env)
          |> elem(0)
        else
          value
          |> Tuple.to_list()
          |> Enum.map(&expand_and_eval_literal_option(&1, caller_env))
          |> List.to_tuple()
        end

      other ->
        other
    end
  end

  defp ast_node?({_, meta, _}) when is_list(meta), do: true
  defp ast_node?(_other), do: false

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
    raw_topology = Keyword.get(opts, :topology, %{})
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
      |> __MODULE__.expand_and_eval_literal_option(__CALLER__)

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

  Structural topology changes advance `topology.version`; no-op replacements
  preserve the current version.
  """
  @spec put_topology(Agent.t(), Topology.t()) :: {:ok, Agent.t()} | {:error, term()}
  def put_topology(%Agent{} = agent, %Topology{} = topology) do
    with {:ok, current_topology} <- fetch_topology(agent),
         {:ok, instance} <- pod_plugin_instance(agent.agent_module),
         {:ok, pod_state} <- fetch_state(agent) do
      normalized_topology = normalize_mutated_topology(current_topology, topology)
      {:ok, persist_topology(agent, instance.state_key, pod_state, normalized_topology)}
    end
  end

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
  def update_topology(%Agent{} = agent, fun) when is_function(fun, 1) do
    with {:ok, topology} <- fetch_topology(agent),
         {:ok, new_topology} <- normalize_topology_update(fun.(topology)) do
      with {:ok, instance} <- pod_plugin_instance(agent.agent_module),
           {:ok, pod_state} <- fetch_state(agent) do
        normalized_topology = normalize_mutated_topology(topology, new_topology)
        {:ok, persist_topology(agent, instance.state_key, pod_state, normalized_topology)}
      end
    end
  end

  @doc """
  Applies live topology mutations to a running pod and waits for runtime work to finish.

  `server` follows the same resolution rules as `Jido.AgentServer.state/1` and
  `Jido.AgentServer.call/3`. Pass the running pod pid, a locally registered
  server name, or another resolvable runtime server reference. Raw string ids
  still require explicit registry lookup before use.
  """
  @spec mutate(AgentServer.server(), [Mutation.t() | term()], keyword()) ::
          {:ok, mutation_report()} | {:error, mutation_report() | term()}
  def mutate(server, ops, opts \\ []) when is_list(opts) do
    signal =
      Signal.new!(
        "pod.mutate",
        %{ops: ops, opts: Map.new(opts)},
        source: "/jido/pod/mutate"
      )

    await_timeout =
      Keyword.get(opts, :await_timeout, Keyword.get(opts, :timeout, :timer.seconds(30)))

    with {:ok, lock} <- acquire_external_mutation_lock(server) do
      with {:ok, state} <- AgentServer.state(server),
           {:ok, synced_lock} <- sync_external_mutation_lock(lock, server, state) do
        with {:ok, pod_state} <- fetch_state(state),
             :ok <- ensure_mutation_idle(pod_state),
             {:ok, _agent} <- AgentServer.call(server, signal) do
          await_mutation(server, await_timeout, synced_lock)
        else
          {:error, _reason} = error ->
            release_external_mutation_lock(synced_lock)
            error
        end
      else
        {:error, _reason} = error ->
          release_external_mutation_lock(lock)
          error
      end
    end
  end

  @doc """
  Builds state ops and runtime effects for an in-turn pod mutation.
  """
  @spec mutation_effects(Agent.t(), [Mutation.t() | term()], keyword()) ::
          {:ok, [struct()]} | {:error, term()}
  def mutation_effects(%Agent{} = agent, ops, opts \\ []) when is_list(opts) do
    with {:ok, pod_state} <- fetch_state(agent),
         :ok <- ensure_mutation_idle(pod_state),
         {:ok, topology} <- fetch_topology(agent),
         {:ok, plan} <- Planner.plan(topology, ops) do
      mutation_state = %{id: plan.mutation_id, status: :running, report: plan.report, error: nil}

      {:ok,
       [
         StateOp.set_path([@pod_state_key, :topology], plan.final_topology),
         StateOp.set_path([@pod_state_key, :topology_version], plan.final_topology.version),
         StateOp.set_path([@pod_state_key, :mutation], mutation_state),
         ApplyMutation.new!(plan, opts)
       ]}
    end
  end

  @doc false
  @spec mark_mutation_lock(Agent.t(), map(), String.t() | nil) :: :ok
  def mark_mutation_lock(%Agent{id: id}, context, mutation_id) when is_map(context) do
    ensure_mutation_lock_table!()

    agent_server_pid = Map.get(context, :agent_server_pid)

    :ets.insert(@mutation_lock_table, {id, mutation_id || true})

    if is_pid(agent_server_pid) do
      :ets.insert(@mutation_lock_table, {{:pid, agent_server_pid}, mutation_id || true})
    end

    :ok
  end

  @doc """
  Returns runtime snapshots for every node in a running pod.
  """
  @spec nodes(AgentServer.server()) :: {:ok, %{node_name() => node_snapshot()}} | {:error, term()}
  def nodes(server) do
    with {:ok, state} <- AgentServer.state(server),
         {:ok, topology} <- fetch_topology(state) do
      {:ok, build_node_snapshots(state, topology)}
    end
  end

  @doc """
  Looks up a node's live process if it is currently running.
  """
  @spec lookup_node(AgentServer.server(), node_name()) :: {:ok, pid()} | :error | {:error, term()}
  def lookup_node(server, name) when is_node_name(name) do
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
  @spec ensure_node(AgentServer.server(), node_name(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def ensure_node(server, name, opts \\ []) when is_node_name(name) and is_list(opts) do
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

  @doc false
  @spec execute_mutation_plan(State.t(), Plan.t(), keyword()) :: {:ok, State.t()}
  def execute_mutation_plan(%State{} = state, %Plan{} = plan, opts \\ []) when is_list(opts) do
    {state, stop_result} =
      execute_stop_waves(
        self(),
        state,
        plan.current_topology,
        plan.removed_nodes,
        plan.stop_waves,
        plan.mutation_id,
        opts,
        true
      )

    {state, start_result} =
      case plan.start_requested do
        [] ->
          {state,
           {:ok,
            %{
              requested: [],
              waves: [],
              nodes: %{},
              failures: %{},
              completed: [],
              failed: [],
              pending: []
            }}}

        _names ->
          case execute_runtime_plan_locally(
                 state,
                 plan.final_topology,
                 plan.start_requested,
                 plan.start_waves,
                 opts
               ) do
            {:ok, next_state, report} -> {next_state, {:ok, report}}
            {:error, next_state, report} -> {next_state, {:error, report}}
          end
      end

    report = complete_mutation_report(plan.report, stop_result, start_result)
    mutation_status = if report.status == :completed, do: :completed, else: :failed

    mutation_state = %{
      id: plan.mutation_id,
      status: mutation_status,
      report: report,
      error: if(mutation_status == :failed, do: report, else: nil)
    }

    clear_mutation_lock(state)
    agent = put_in(state.agent.state, [@pod_state_key, :mutation], mutation_state)
    {:ok, State.update_agent(state, %{state.agent | state: agent})}
  end

  @doc false
  @spec teardown_runtime(AgentServer.server(), keyword()) ::
          {:ok, map()} | {:error, map() | term()}
  def teardown_runtime(server, opts \\ []) when is_list(opts) do
    with {:ok, state} <- AgentServer.state(server),
         {:ok, topology} <- fetch_topology(state),
         {:ok, server_pid} <- resolve_runtime_server(server, state),
         {:ok, stop_waves} <- Planner.stop_waves(topology, Map.keys(topology.nodes)) do
      {_state, stop_result} =
        execute_stop_waves(
          server_pid,
          state,
          topology,
          topology.nodes,
          stop_waves,
          "pod-teardown",
          opts,
          false
        )

      report = %{
        requested: Map.keys(topology.nodes),
        waves: stop_waves,
        stopped: Enum.sort(stop_result.stopped),
        failures: stop_result.failures
      }

      if map_size(report.failures) == 0 do
        {:ok, report}
      else
        {:error, report}
      end
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

  defp persist_topology(%Agent{} = agent, state_key, pod_state, %Topology{} = topology)
       when is_atom(state_key) and is_map(pod_state) do
    updated_state =
      pod_state
      |> Map.put(:topology, topology)
      |> Map.put(:topology_version, topology.version)

    %{agent | state: Map.put(agent.state, state_key, updated_state)}
  end

  @doc false
  @spec normalize_mutated_topology(Topology.t(), Topology.t()) :: Topology.t()
  def normalize_mutated_topology(%Topology{} = current, %Topology{} = updated) do
    if topology_changed?(current, updated) do
      %{updated | version: max(updated.version, current.version + 1)}
    else
      %{updated | version: current.version}
    end
  end

  defp ensure_mutation_idle(%{mutation: %{status: status}})
       when status in [:running, :queued] do
    {:error, :mutation_in_progress}
  end

  defp ensure_mutation_idle(_pod_state), do: :ok

  defp await_mutation(server, await_timeout, lock) do
    case AgentServer.await_completion(
           server,
           timeout: await_timeout,
           status_path: [@pod_state_key, :mutation, :status],
           result_path: [@pod_state_key, :mutation, :report],
           error_path: [@pod_state_key, :mutation, :error]
         ) do
      {:ok, %{status: :completed, result: result}} ->
        {:ok, result}

      {:ok, %{status: :failed, result: result}} ->
        {:error, result}

      {:error, :not_found} = error ->
        release_external_mutation_lock(lock)
        error

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp acquire_external_mutation_lock(server) do
    ensure_mutation_lock_table!()

    keys = external_mutation_lock_keys(server)

    if insert_lock_keys(keys) do
      {:ok, %{keys: keys}}
    else
      {:error, :mutation_in_progress}
    end
  end

  defp external_mutation_lock_keys(server) do
    case server do
      pid when is_pid(pid) -> [{:pid, pid}]
      id when is_binary(id) -> [id]
      _other -> []
    end
  end

  defp sync_external_mutation_lock(%{keys: keys} = lock, server, %State{} = state) do
    missing_keys =
      canonical_external_mutation_lock_keys(server, state)
      |> Enum.reject(&(&1 in keys))

    case acquire_missing_lock_keys(missing_keys, []) do
      {:ok, acquired_keys} ->
        {:ok, %{lock | keys: Enum.uniq(keys ++ acquired_keys)}}

      {:error, acquired_keys} ->
        release_external_mutation_lock(%{keys: keys ++ acquired_keys})
        {:error, :mutation_in_progress}
    end
  end

  defp canonical_external_mutation_lock_keys(server, %State{id: id, jido: jido}) do
    pid_key =
      case server do
        pid when is_pid(pid) ->
          {:pid, pid}

        id_value when is_binary(id_value) and is_atom(jido) ->
          case Jido.whereis(jido, id) do
            pid when is_pid(pid) -> {:pid, pid}
            _other -> nil
          end

        _other ->
          nil
      end

    [id, pid_key]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp acquire_missing_lock_keys([], acquired), do: {:ok, Enum.reverse(acquired)}

  defp acquire_missing_lock_keys([key | rest], acquired) do
    if :ets.insert_new(@mutation_lock_table, {key, true}) do
      acquire_missing_lock_keys(rest, [key | acquired])
    else
      {:error, Enum.reverse(acquired)}
    end
  end

  defp insert_lock_keys([]), do: true

  defp insert_lock_keys(keys) do
    Enum.all?(keys, &:ets.insert_new(@mutation_lock_table, {&1, true}))
  end

  defp release_external_mutation_lock(%{keys: keys}) do
    ensure_mutation_lock_table!()
    Enum.each(keys, &:ets.delete(@mutation_lock_table, &1))
    :ok
  end

  defp clear_mutation_lock(%State{id: id}) do
    ensure_mutation_lock_table!()
    :ets.delete(@mutation_lock_table, id)
    :ets.delete(@mutation_lock_table, {:pid, self()})
    :ok
  end

  defp ensure_mutation_lock_table! do
    case :ets.whereis(@mutation_lock_table) do
      :undefined ->
        try do
          :ets.new(@mutation_lock_table, [:named_table, :public, :set, read_concurrency: true])
        rescue
          ArgumentError -> @mutation_lock_table
        end

      _tid ->
        @mutation_lock_table
    end
  end

  defp topology_changed?(%Topology{} = left, %Topology{} = right) do
    drop_topology_version(left) != drop_topology_version(right)
  end

  defp drop_topology_version(%Topology{} = topology) do
    %{topology | version: 0}
  end

  defp fetch_node(%Topology{} = topology, name) when is_node_name(name) do
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

  defp execute_runtime_plan_locally(state, topology, requested_names, waves, opts) do
    initial_report = %{
      requested: Enum.uniq(requested_names),
      waves: waves,
      nodes: %{},
      failures: %{},
      completed: [],
      failed: [],
      pending: List.flatten(waves)
    }

    Enum.reduce_while(Enum.with_index(waves), {:ok, state, initial_report}, fn {wave, wave_index},
                                                                               {:ok, state_acc,
                                                                                report} ->
      {state_after_wave, wave_results} =
        Enum.reduce(wave, {state_acc, []}, fn name, {state_wave, results} ->
          case ensure_planned_node_locally(
                 state_wave,
                 topology,
                 requested_names,
                 name,
                 report,
                 opts
               ) do
            {:ok, {new_state, result}} ->
              {new_state, [{:ok, name, result} | results]}

            {:error, new_state, reason} ->
              {new_state, [{:error, name, reason} | results]}

            {:error, reason} ->
              {state_wave, [{:error, name, reason} | results]}
          end
        end)

      updated_report = merge_wave_results(report, Enum.reverse(wave_results), waves, wave_index)

      if updated_report.failures == %{} do
        {:cont, {:ok, state_after_wave, updated_report}}
      else
        {:halt, {:error, state_after_wave, updated_report}}
      end
    end)
    |> case do
      {:ok, next_state, report} -> {:ok, next_state, report}
      {:error, next_state, report} -> {:error, next_state, report}
    end
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

  defp ensure_planned_node_locally(state, topology, requested_names, name, report, opts) do
    with {:ok, node} <- fetch_node(topology, name) do
      snapshot = build_node_snapshot(state, topology, name, node)
      source = snapshot_source(snapshot)

      observe_pod_operation(
        [:jido, :pod, :node, :ensure],
        node_event_metadata(state, node, name, source, snapshot.owner),
        fn ->
          with :ok <- ensure_runtime_supported(node, name) do
            do_ensure_planned_node_locally(
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
          {:ok, {_state, result}} ->
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

  defp do_ensure_planned_node_locally(
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
      ensure_planned_pod_node_locally(
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
      ensure_planned_agent_node_locally(
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

  defp ensure_planned_agent_node_locally(
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
        {:ok, {state, ensure_result(name, snapshot.running_pid, :adopted, snapshot.owner)}}

      :misplaced ->
        {:error, state, misplaced_node_reason(name, snapshot)}

      _status ->
        initial_state = node_initial_state(requested_names, name, node, opts)
        key = node_key(state, name)

        with {:ok, parent_pid} <- resolve_parent_pid(self(), state, topology, name, report),
             {:ok, pid} <- get_managed_node(node.manager, key, initial_state: initial_state),
             {:ok, next_state, ^pid} <-
               adopt_runtime_child_locally(parent_pid, pid, name, node.meta, state, topology) do
          {:ok, {next_state, ensure_result(name, pid, snapshot_source(snapshot), snapshot.owner)}}
        else
          {:error, reason} -> {:error, state, reason}
        end
    end
  end

  defp ensure_planned_pod_node_locally(
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
            {:ok, {state, ensure_result(name, snapshot.running_pid, :adopted, snapshot.owner)}}
          else
            {:error, reason} -> {:error, state, reason}
          end

        :misplaced ->
          {:error, state, misplaced_node_reason(name, snapshot)}

        _status ->
          initial_state = node_initial_state(requested_names, name, node, opts)
          key = node_key(state, name)

          with {:ok, parent_pid} <- resolve_parent_pid(self(), state, topology, name, report),
               {:ok, pid} <- get_managed_node(node.manager, key, initial_state: initial_state),
               {:ok, next_state, ^pid} <-
                 adopt_runtime_child_locally(parent_pid, pid, name, node.meta, state, topology),
               {:ok, _nested_report} <- reconcile_nested_pod(pid, node, next_state, opts) do
            {:ok,
             {next_state, ensure_result(name, pid, snapshot_source(snapshot), snapshot.owner)}}
          else
            {:error, reason} -> {:error, state, reason}
          end
      end
    else
      {:error, reason} -> {:error, state, reason}
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

  defp adopt_runtime_child_locally(parent_pid, child_pid, name, meta, state, topology) do
    if parent_pid == self() do
      local_adopt_child(child_pid, name, meta, state, topology)
    else
      case AgentServer.adopt_child(parent_pid, child_pid, name, meta) do
        {:ok, ^child_pid} ->
          {:ok, state, child_pid}

        {:error, _reason} = error ->
          case build_node_snapshot(state, topology, name) do
            %{status: :adopted, running_pid: ^child_pid} ->
              {:ok, state, child_pid}

            _snapshot ->
              error
          end
      end
    end
  end

  defp local_adopt_child(child_pid, name, meta, state, topology) do
    case State.get_child(state, name) do
      nil ->
        parent_ref =
          ParentRef.new!(%{
            pid: self(),
            id: state.id,
            tag: name,
            meta: meta
          })

        with {:ok, child_runtime} <- AgentServer.adopt_parent(child_pid, parent_ref) do
          child_info =
            ChildInfo.new!(%{
              pid: child_pid,
              ref: Process.monitor(child_pid),
              module: child_runtime.agent_module,
              id: child_runtime.id,
              tag: name,
              meta: meta
            })

          {:ok, State.add_child(state, name, child_info), child_pid}
        end

      _child ->
        case build_node_snapshot(state, topology, name) do
          %{status: :adopted, running_pid: ^child_pid} ->
            {:ok, state, child_pid}

          _snapshot ->
            {:error, {:tag_in_use, name}}
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
    actual_parent = actual_parent_ref(state, topology, name)
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

  defp actual_parent_ref(%State{} = state, %Topology{} = topology, name)
       when is_node_name(name) do
    case RuntimeStore.fetch(state.jido, :relationships, node_id(state, name)) do
      {:ok, %{parent_id: parent_id, tag: tag}} when is_binary(parent_id) ->
        %{id: parent_id, pid: resolve_parent_runtime_pid(state, topology, parent_id), tag: tag}

      {:ok, _other} ->
        nil

      :error ->
        nil
    end
  end

  defp resolve_parent_runtime_pid(%State{id: state_id, registry: registry}, _topology, parent_id)
       when parent_id == state_id do
    AgentServer.whereis(registry, state_id)
  end

  defp resolve_parent_runtime_pid(%State{} = state, %Topology{} = topology, parent_id)
       when is_binary(parent_id) do
    case Enum.find(topology.nodes, fn {candidate_name, _node} ->
           node_id(state, candidate_name) == parent_id
         end) do
      {owner_name, %Node{manager: manager}} ->
        running_child_pid(manager, node_key(state, owner_name))

      nil ->
        Jido.whereis(state.jido, parent_id)
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

  defp expected_parent_ref(%State{} = state, name, owner_name)
       when is_node_name(owner_name) do
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

  defp execute_stop_waves(
         root_server_pid,
         %State{} = state,
         %Topology{} = topology,
         removed_nodes,
         stop_waves,
         mutation_id,
         opts,
         local_root?
       )
       when is_pid(root_server_pid) and is_map(removed_nodes) and is_list(stop_waves) and
              is_list(opts) do
    Enum.reduce(stop_waves, {state, %{stopped: [], failures: %{}}}, fn wave,
                                                                       {state_acc, report_acc} ->
      Enum.reduce(wave, {state_acc, report_acc}, fn name, {state_wave, report_wave} ->
        node = Map.fetch!(removed_nodes, name)

        case stop_planned_node(
               root_server_pid,
               state_wave,
               topology,
               name,
               node,
               mutation_id,
               opts,
               local_root?
             ) do
          {:ok, new_state} ->
            {new_state, %{report_wave | stopped: append_unique(report_wave.stopped, name)}}

          {:error, new_state, reason} ->
            {new_state, %{report_wave | failures: Map.put(report_wave.failures, name, reason)}}
        end
      end)
    end)
  end

  defp stop_planned_node(
         root_server_pid,
         %State{} = state,
         %Topology{} = topology,
         name,
         %Node{} = node,
         mutation_id,
         opts,
         local_root?
       ) do
    snapshot = build_node_snapshot(state, topology, name, node)

    case snapshot.running_pid do
      pid when is_pid(pid) ->
        with :ok <- maybe_teardown_nested_runtime(node, pid, opts),
             {:ok, next_state} <-
               dispatch_stop_to_parent(
                 root_server_pid,
                 state,
                 topology,
                 name,
                 snapshot,
                 mutation_id,
                 local_root?
               ),
             :ok <-
               await_process_exit(
                 pid,
                 Keyword.get(opts, :stop_timeout, Keyword.get(opts, :timeout, :timer.seconds(30)))
               ) do
          {:ok, next_state}
        else
          {:error, reason} -> {:error, state, reason}
        end

      _other ->
        {:ok, state}
    end
  end

  defp maybe_teardown_nested_runtime(%Node{kind: :pod}, pid, opts) when is_pid(pid) do
    nested_opts =
      opts |> Keyword.take([:timeout, :stop_timeout]) |> Keyword.delete(:initial_state)

    case teardown_runtime(pid, nested_opts) do
      {:ok, _report} -> :ok
      {:error, report} -> {:error, {:nested_pod_teardown_failed, report}}
    end
  end

  defp maybe_teardown_nested_runtime(%Node{}, _pid, _opts), do: :ok

  defp dispatch_stop_to_parent(
         root_server_pid,
         %State{} = state,
         %Topology{} = topology,
         name,
         snapshot,
         mutation_id,
         local_root?
       ) do
    parent_pid = resolve_stop_parent_pid(root_server_pid, state, topology, name, snapshot)
    reason = {:pod_mutation, mutation_id}

    cond do
      is_pid(parent_pid) and parent_pid == root_server_pid and local_root? ->
        signal =
          Signal.new!(
            "jido.pod.mutation.stop",
            %{mutation_id: mutation_id, node: name},
            source: "/pod/#{state.id}"
          )

        StopChildRuntime.exec(name, reason, signal, state)

      is_pid(parent_pid) ->
        case AgentServer.stop_child(parent_pid, name, reason) do
          :ok -> {:ok, state}
          {:error, stop_reason} -> {:error, stop_reason}
        end

      is_pid(snapshot.running_pid) ->
        direct_stop_child(state, name, snapshot.running_pid, reason)

      true ->
        {:error,
         Jido.Error.validation_error(
           "Could not resolve a running parent for pod node teardown.",
           details: %{node: name, actual_parent: snapshot.actual_parent}
         )}
    end
  end

  defp resolve_stop_parent_pid(
         root_server_pid,
         %State{} = state,
         %Topology{} = topology,
         name,
         snapshot
       ) do
    cond do
      is_map(snapshot.actual_parent) and is_pid(snapshot.actual_parent.pid) ->
        snapshot.actual_parent.pid

      true ->
        case Topology.owner_of(topology, name) do
          :root ->
            root_server_pid

          {:ok, owner_name} ->
            running_child_pid(topology.nodes[owner_name].manager, node_key(state, owner_name))

          :error ->
            nil
        end
    end
  end

  defp direct_stop_child(%State{} = state, name, pid, reason) when is_pid(pid) do
    _ = RuntimeStore.delete(state.jido, :relationships, node_id(state, name))

    stop_signal =
      Signal.new!(
        "jido.agent.stop",
        %{reason: {:shutdown, reason}},
        source: "/pod/#{state.id}"
      )

    case AgentServer.cast(pid, stop_signal) do
      :ok -> {:ok, state}
      {:error, cast_reason} -> {:error, cast_reason}
    end
  end

  defp await_process_exit(pid, timeout) when is_pid(pid) do
    if Process.alive?(pid) do
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} ->
          :ok
      after
        timeout ->
          Process.demonitor(ref, [:flush])
          {:error, :stop_timeout}
      end
    else
      :ok
    end
  end

  defp complete_mutation_report(%Report{} = report, stop_result, start_result) do
    stop_failures = Map.get(stop_result, :failures, %{})
    stopped = Map.get(stop_result, :stopped, [])

    {started, start_failures} =
      case start_result do
        {:ok, reconcile_report} ->
          {started_names_from_reconcile(reconcile_report), %{}}

        {:error, reconcile_report} ->
          {started_names_from_reconcile(reconcile_report), reconcile_report.failures}
      end

    failures = Map.merge(stop_failures, start_failures)
    status = if map_size(failures) == 0, do: :completed, else: :failed

    %Report{
      report
      | status: status,
        started: Enum.sort(started),
        stopped: Enum.sort(stopped),
        failures: failures
    }
  end

  defp started_names_from_reconcile(report) do
    report.nodes
    |> Enum.filter(fn {_name, result} -> result.source == :started end)
    |> Enum.map(&elem(&1, 0))
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
