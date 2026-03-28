defmodule Jido.Pod.Mutation.Planner do
  @moduledoc """
  Pure planner for live pod mutations.
  """

  alias Jido.Pod.Mutation
  alias Jido.Pod.Mutation.{AddNode, Plan, RemoveNode, Report}
  alias Jido.Pod.Topology
  alias Jido.Pod.TopologyState

  defguardp is_node_name(name) when is_atom(name) or is_binary(name)
  @typep node_name_list :: [Mutation.node_name()]

  @spec plan(Topology.t(), [Mutation.t() | term()]) :: {:ok, Plan.t()} | {:error, term()}
  def plan(%Topology{} = topology, ops) do
    with {:ok, normalized_ops} <- Mutation.normalize_ops(ops),
         :ok <- validate_batch_targets(normalized_ops),
         {:ok, final_topology} <- apply_ops(topology, normalized_ops),
         {:ok, validated_final_topology} <- validate_final_topology(final_topology),
         {:ok, added, removed} <- diff_nodes(topology, validated_final_topology),
         {:ok, start_requested, start_waves} <- build_start_plan(validated_final_topology, added),
         {:ok, stop_waves} <- stop_waves(topology, removed) do
      mutation_id = Uniq.UUID.uuid7()

      normalized_final_topology =
        TopologyState.normalize_updated_topology(topology, validated_final_topology)

      report = seed_report(mutation_id, normalized_ops, normalized_final_topology, added, removed)

      {:ok,
       %Plan{
         mutation_id: mutation_id,
         requested_ops: normalized_ops,
         current_topology: topology,
         final_topology: normalized_final_topology,
         added: added,
         removed: removed,
         start_requested: start_requested,
         start_waves: start_waves,
         stop_waves: stop_waves,
         removed_nodes: Map.take(topology.nodes, removed),
         report: report
       }}
    end
  end

  @spec stop_waves(Topology.t(), [Mutation.node_name()]) ::
          {:ok, [[Mutation.node_name()]]} | {:error, term()}
  def stop_waves(_topology, []), do: {:ok, []}

  def stop_waves(%Topology{} = topology, removed) do
    edges =
      Enum.flat_map(removed, fn name ->
        runtime_prerequisites(topology, name)
        |> Enum.filter(&(&1 in removed))
        |> Enum.map(&{&1, name})
      end)

    case topological_layers(removed, edges) do
      {:ok, waves} ->
        {:ok, Enum.reverse(waves)}

      {:error, _reason} ->
        {:error,
         Jido.Error.validation_error(
           "Pod mutation remove set contains cyclic ownership or dependency links.",
           details: %{removed: removed}
         )}
    end
  end

  defp validate_batch_targets(ops) do
    touched =
      Enum.map(ops, fn
        %AddNode{name: name} -> name
        %RemoveNode{name: name} -> name
      end)

    duplicates =
      touched
      |> Enum.frequencies()
      |> Enum.filter(fn {_name, count} -> count > 1 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    case duplicates do
      [] ->
        :ok

      names ->
        {:error,
         Jido.Error.validation_error(
           "Pod mutation batch cannot touch the same node more than once.",
           details: %{names: names}
         )}
    end
  end

  defp apply_ops(%Topology{} = topology, ops) do
    Enum.reduce_while(ops, {:ok, topology}, fn op, {:ok, acc} ->
      case apply_op(acc, op) do
        {:ok, next_topology} -> {:cont, {:ok, next_topology}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp apply_op(%Topology{} = topology, %AddNode{
         name: name,
         node: node,
         owner: owner,
         depends_on: depends_on
       }) do
    with :ok <- ensure_node_absent(topology, name),
         {:ok, next_topology} <- Topology.put_node(topology, name, node),
         {:ok, next_topology} <- maybe_put_owner(next_topology, owner, name),
         {:ok, next_topology} <- put_dependencies(next_topology, name, depends_on) do
      {:ok, next_topology}
    end
  end

  defp apply_op(%Topology{} = topology, %RemoveNode{name: name}) do
    case Topology.fetch_node(topology, name) do
      {:ok, _node} ->
        remove_owned_subtree(topology, [name], [])

      :error ->
        {:error,
         Jido.Error.validation_error(
           "Pod mutation remove target does not exist.",
           details: %{name: name}
         )}
    end
  end

  defp ensure_node_absent(%Topology{} = topology, name) do
    case Topology.fetch_node(topology, name) do
      {:ok, _node} ->
        {:error,
         Jido.Error.validation_error(
           "Pod mutation add target already exists.",
           details: %{name: name}
         )}

      :error ->
        :ok
    end
  end

  defp maybe_put_owner(%Topology{} = topology, nil, _name), do: {:ok, topology}

  defp maybe_put_owner(%Topology{} = topology, owner, name) when is_node_name(owner) do
    Topology.put_link(topology, {:owns, owner, name})
  end

  defp put_dependencies(%Topology{} = topology, _name, []), do: {:ok, topology}

  defp put_dependencies(%Topology{} = topology, name, dependencies) when is_list(dependencies) do
    Enum.reduce_while(dependencies, {:ok, topology}, fn dependency, {:ok, acc} ->
      case Topology.put_link(acc, {:depends_on, name, dependency}) do
        {:ok, next_topology} -> {:cont, {:ok, next_topology}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  @spec remove_owned_subtree(Topology.t(), [Mutation.node_name()], node_name_list()) ::
          {:ok, Topology.t()} | {:error, term()}
  defp remove_owned_subtree(%Topology{} = topology, [], visited),
    do: {:ok, delete_all(topology, visited)}

  defp remove_owned_subtree(%Topology{} = topology, [name | rest], visited) do
    if name in visited do
      remove_owned_subtree(topology, rest, visited)
    else
      owned_children = Topology.owned_children(topology, name)
      remove_owned_subtree(topology, owned_children ++ rest, [name | visited])
    end
  end

  @spec delete_all(Topology.t(), node_name_list()) :: Topology.t()
  defp delete_all(%Topology{} = topology, visited) do
    Enum.reduce(Enum.reverse(visited), topology, fn name, acc ->
      Topology.delete_node(acc, name)
    end)
  end

  defp validate_final_topology(%Topology{} = topology) do
    Topology.new(%{
      name: topology.name,
      nodes:
        Map.new(topology.nodes, fn {name, node} ->
          {name, Map.from_struct(node)}
        end),
      links: Enum.map(topology.links, &Map.from_struct/1),
      defaults: topology.defaults,
      version: topology.version
    })
  end

  defp diff_nodes(%Topology{} = current, %Topology{} = final) do
    current_names = Map.keys(current.nodes)
    final_names = Map.keys(final.nodes)

    {:ok, Enum.sort(final_names -- current_names), Enum.sort(current_names -- final_names)}
  end

  defp build_start_plan(_topology, []), do: {:ok, [], []}

  defp build_start_plan(%Topology{} = topology, added) do
    start_requested =
      Enum.filter(added, fn name ->
        case Topology.fetch_node(topology, name) do
          {:ok, node} -> node.activation == :eager
          :error -> false
        end
      end)

    case start_requested do
      [] ->
        {:ok, [], []}

      names ->
        with {:ok, waves} <- Topology.reconcile_waves(topology, names), do: {:ok, names, waves}
    end
  end

  defp runtime_prerequisites(%Topology{} = topology, name) do
    owner =
      case Topology.owner_of(topology, name) do
        {:ok, owner_name} -> [owner_name]
        _other -> []
      end

    owner ++ Topology.dependencies_of(topology, name)
  end

  defp topological_layers(node_names, edges) when is_list(node_names) and is_list(edges) do
    ordered_nodes = node_names |> Enum.uniq() |> Enum.sort()

    adjacency =
      Enum.reduce(edges, %{}, fn {prereq, dependent}, acc ->
        Map.update(acc, prereq, [dependent], &[dependent | &1])
      end)

    indegree =
      Enum.reduce(ordered_nodes, %{}, fn name, acc -> Map.put(acc, name, 0) end)
      |> then(fn base ->
        Enum.reduce(edges, base, fn {_prereq, dependent}, acc ->
          Map.update!(acc, dependent, &(&1 + 1))
        end)
      end)

    do_topological_layers(ordered_nodes, adjacency, indegree, [])
  end

  defp do_topological_layers([], _adjacency, _indegree, acc), do: {:ok, Enum.reverse(acc)}

  defp do_topological_layers(remaining, adjacency, indegree, acc) do
    ready =
      remaining
      |> Enum.filter(&(Map.get(indegree, &1, 0) == 0))
      |> Enum.sort()

    case ready do
      [] ->
        {:error, :cyclic_dependencies}

      _ready ->
        next_indegree =
          Enum.reduce(ready, indegree, fn node, indegree_acc ->
            Enum.reduce(Map.get(adjacency, node, []), indegree_acc, fn dependent, inner_acc ->
              Map.update!(inner_acc, dependent, &(&1 - 1))
            end)
          end)

        next_remaining = remaining -- ready
        do_topological_layers(next_remaining, adjacency, next_indegree, [ready | acc])
    end
  end

  defp seed_report(mutation_id, ops, topology, added, removed) do
    %Report{
      mutation_id: mutation_id,
      status: :running,
      topology_version: topology.version,
      requested_ops: ops,
      added: added,
      removed: removed,
      started: [],
      stopped: [],
      failures: %{}
    }
  end
end
