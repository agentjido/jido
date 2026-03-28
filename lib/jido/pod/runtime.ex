defmodule Jido.Pod.Runtime do
  @moduledoc false

  alias Jido.Agent.InstanceManager
  alias Jido.AgentServer
  alias Jido.AgentServer.{ChildInfo, ParentRef, StopChildRuntime}
  alias Jido.AgentServer.State
  alias Jido.Observe
  alias Jido.Pod.Mutation.Plan
  alias Jido.Pod.Mutation.Planner
  alias Jido.Pod.Mutation.Report
  alias Jido.Pod.Mutable
  alias Jido.Pod.Plugin
  alias Jido.Pod.Topology
  alias Jido.Pod.Topology.Node
  alias Jido.Pod.TopologyState
  alias Jido.RuntimeStore
  alias Jido.Signal

  defguardp is_node_name(name) when is_atom(name) or is_binary(name)

  @pod_state_key Plugin.state_key_atom()

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
          {state, {:ok, empty_reconcile_report()}}

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

    :ok = Mutable.clear_mutation_lock(state)

    agent_state = put_in(state.agent.state, [@pod_state_key, :mutation], mutation_state)
    {:ok, State.update_agent(state, %{state.agent | state: agent_state})}
  end

  @spec teardown_runtime(AgentServer.server(), keyword()) ::
          {:ok, map()} | {:error, map() | term()}
  def teardown_runtime(server, opts \\ []) when is_list(opts) do
    with {:ok, state} <- AgentServer.state(server),
         {:ok, topology} <- TopologyState.fetch_topology(state),
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
        {:ok, {state, ensure_result(snapshot.running_pid, :adopted, snapshot.owner)}}

      :misplaced ->
        {:error, state, misplaced_node_reason(name, snapshot)}

      _status ->
        initial_state = node_initial_state(requested_names, name, node, opts)
        key = node_key(state, name)
        get_opts = [partition: state.partition, initial_state: initial_state]

        with {:ok, parent_pid} <- resolve_parent_pid(self(), topology, name, report),
             {:ok, pid} <- get_managed_node(node.manager, key, get_opts),
             {:ok, next_state, ^pid} <-
               adopt_runtime_child_locally(parent_pid, pid, name, node.meta, state, topology) do
          {:ok, {next_state, ensure_result(pid, snapshot_source(snapshot), snapshot.owner)}}
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
            {:ok, {state, ensure_result(snapshot.running_pid, :adopted, snapshot.owner)}}
          else
            {:error, reason} -> {:error, state, reason}
          end

        :misplaced ->
          {:error, state, misplaced_node_reason(name, snapshot)}

        _status ->
          initial_state = node_initial_state(requested_names, name, node, opts)
          key = node_key(state, name)
          get_opts = [partition: state.partition, initial_state: initial_state]

          with {:ok, parent_pid} <- resolve_parent_pid(self(), topology, name, report),
               {:ok, pid} <- get_managed_node(node.manager, key, get_opts),
               {:ok, next_state, ^pid} <-
                 adopt_runtime_child_locally(parent_pid, pid, name, node.meta, state, topology),
               {:ok, _nested_report} <- reconcile_nested_pod(pid, node, state, opts) do
            {:ok, {next_state, ensure_result(pid, snapshot_source(snapshot), snapshot.owner)}}
          else
            {:error, reason} -> {:error, state, reason}
          end
      end
    else
      {:error, reason} -> {:error, state, reason}
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
            partition: state.partition,
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
              partition: child_runtime.partition,
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
            running_child_pid(
              topology.nodes[owner_name].manager,
              node_key(state, owner_name),
              partition: state.partition
            )

          :error ->
            nil
        end
    end
  end

  defp direct_stop_child(%State{} = state, name, pid, reason) when is_pid(pid) do
    _ =
      RuntimeStore.delete(
        state.jido,
        :relationships,
        Jido.partition_key(node_id(state, name), state.partition)
      )

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

  defp empty_reconcile_report do
    %{
      requested: [],
      waves: [],
      nodes: %{},
      failures: %{},
      completed: [],
      failed: [],
      pending: []
    }
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
