defmodule Jido.Pod.Runtime do
  @moduledoc false

  alias Jido.Agent.InstanceManager
  alias Jido.AgentServer
  alias Jido.AgentServer.State
  alias Jido.Observe
  alias Jido.Pod.Topology
  alias Jido.Pod.Topology.Node
  alias Jido.Pod.TopologyState
  alias Jido.RuntimeStore

  defguardp is_node_name(name) when is_atom(name) or is_binary(name)

  def nodes(server) do
    with {:ok, state} <- AgentServer.state(server),
         {:ok, topology} <- TopologyState.fetch_topology(state) do
      {:ok, build_node_snapshots(state, topology)}
    end
  end

  def lookup_node(server, name) when is_node_name(name) do
    with {:ok, state} <- AgentServer.state(server),
         {:ok, topology} <- TopologyState.fetch_topology(state),
         {:ok, node} <- fetch_node(topology, name),
         :ok <- ensure_runtime_supported(node, name) do
      case Map.get(build_node_snapshots(state, topology), name) do
        nil -> {:error, :unknown_node}
        %{running_pid: pid} when is_pid(pid) -> {:ok, pid}
        _snapshot -> :error
      end
    end
  end

  def ensure_node(server, name, opts \\ []) when is_node_name(name) and is_list(opts) do
    with {:ok, state} <- AgentServer.state(server),
         {:ok, topology} <- TopologyState.fetch_topology(state),
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

  def reconcile(server, opts \\ []) when is_list(opts) do
    with {:ok, state} <- AgentServer.state(server),
         {:ok, topology} <- TopologyState.fetch_topology(state),
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
            case TopologyState.pod_plugin_instance(module) do
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

  defp running_child_pid(manager, key, opts) do
    try do
      case InstanceManager.lookup(manager, key, opts) do
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
        {:ok, ensure_result(snapshot.running_pid, :adopted, snapshot.owner)}

      :misplaced ->
        {:error, misplaced_node_reason(name, snapshot)}

      _status ->
        initial_state = node_initial_state(requested_names, name, node, opts)
        key = node_key(state, name)
        get_opts = [partition: state.partition, initial_state: initial_state]

        with {:ok, parent_pid} <- resolve_parent_pid(server_pid, topology, name, report),
             {:ok, pid} <- get_managed_node(node.manager, key, get_opts),
             {:ok, ^pid} <- adopt_runtime_child(parent_pid, pid, name, node.meta, state, topology) do
          {:ok, ensure_result(pid, snapshot_source(snapshot), snapshot.owner)}
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
            {:ok, ensure_result(snapshot.running_pid, :adopted, snapshot.owner)}
          end

        :misplaced ->
          {:error, misplaced_node_reason(name, snapshot)}

        _status ->
          initial_state = node_initial_state(requested_names, name, node, opts)
          key = node_key(state, name)
          get_opts = [partition: state.partition, initial_state: initial_state]

          with {:ok, parent_pid} <- resolve_parent_pid(server_pid, topology, name, report),
               {:ok, pid} <- get_managed_node(node.manager, key, get_opts),
               {:ok, ^pid} <-
                 adopt_runtime_child(parent_pid, pid, name, node.meta, state, topology),
               {:ok, _nested_report} <- reconcile_nested_pod(pid, node, state, opts) do
            {:ok, ensure_result(pid, snapshot_source(snapshot), snapshot.owner)}
          end
      end
    end
  end

  defp resolve_parent_pid(server_pid, topology, name, report) do
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
        %Node{} = existing_node -> existing_node
        _other -> topology.nodes[name]
      end

    key = node_key(state, name)
    running_pid = running_child_pid(node.manager, key, partition: state.partition)
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
    case RuntimeStore.fetch(
           state.jido,
           :relationships,
           Jido.partition_key(node_id(state, name), state.partition)
         ) do
      {:ok, %{parent_id: parent_id, tag: tag} = binding} when is_binary(parent_id) ->
        parent_partition = Map.get(binding, :parent_partition, state.partition)

        %{
          id: parent_id,
          partition: parent_partition,
          pid: resolve_parent_runtime_pid(state, topology, parent_id, parent_partition),
          tag: tag
        }

      {:ok, _other} ->
        nil

      :error ->
        nil
    end
  end

  defp resolve_parent_runtime_pid(
         %State{id: state_id, registry: registry, partition: partition},
         _topology,
         parent_id,
         parent_partition
       )
       when parent_id == state_id do
    AgentServer.whereis(registry, state_id, partition: parent_partition || partition)
  end

  defp resolve_parent_runtime_pid(
         %State{} = state,
         %Topology{} = topology,
         parent_id,
         parent_partition
       )
       when is_binary(parent_id) do
    case Enum.find(topology.nodes, fn {candidate_name, _node} ->
           node_id(state, candidate_name) == parent_id
         end) do
      {owner_name, %Node{manager: manager}} ->
        running_child_pid(manager, node_key(state, owner_name), partition: parent_partition)

      nil ->
        Jido.whereis(state.jido, parent_id, partition: parent_partition)
    end
  end

  defp owner_name(%Topology{} = topology, name) do
    case Topology.owner_of(topology, name) do
      {:ok, owner} -> owner
      _other -> nil
    end
  end

  defp expected_parent_ref(%State{} = state, name, nil) do
    %{scope: :pod, name: nil, id: state.id, partition: state.partition, tag: name}
  end

  defp expected_parent_ref(%State{} = state, name, owner_name)
       when is_node_name(owner_name) do
    %{
      scope: :node,
      name: owner_name,
      id: node_id(state, owner_name),
      partition: state.partition,
      tag: name
    }
  end

  defp parent_matches?(
         %{id: actual_id, partition: actual_partition, tag: actual_tag},
         %{id: expected_id, partition: expected_partition, tag: expected_tag}
       ) do
    actual_id == expected_id and actual_partition == expected_partition and
      actual_tag == expected_tag
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

  defp ensure_result(pid, source, owner) when is_pid(pid) do
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
        jido_instance: state.jido,
        jido_partition: state.partition
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

  defp resolve_runtime_server(server, %State{id: id, registry: registry, partition: partition}) do
    if is_pid(server) and Process.alive?(server) do
      {:ok, server}
    else
      case AgentServer.whereis(registry, id, partition: partition) do
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
