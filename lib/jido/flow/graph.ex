defmodule Jido.Flow.Graph do
  @moduledoc false

  alias Jido.Flow.{Component, Value}

  @type named_component :: {String.t(), Component.component_node()}
  @type components :: %{optional(String.t()) => Component.component_node()}

  @type analysis :: %{
          levels: %{optional(String.t()) => non_neg_integer()},
          remaining: [String.t()],
          ordered: [named_component()] | nil,
          dependencies: %{optional(String.t()) => [String.t()]},
          terminals: [String.t()]
        }

  @doc false
  @spec canonical_components(components()) :: [named_component()]
  def canonical_components(components) when is_map(components) do
    %{ordered: ordered, remaining: []} = analyze(components)
    ordered
  end

  @doc false
  @spec analyze(components()) :: analysis()
  def analyze(components) when is_map(components) do
    dependencies =
      Map.new(components, fn {name, node} -> {name, effective_dependencies(node)} end)

    graph = dependency_graph(dependencies)
    blocked = blocked_vertices(graph, components)

    levels =
      graph
      |> Multigraph.delete_vertices(blocked)
      |> Multigraph.topsort()
      |> Enum.reduce(%{}, fn name, levels ->
        level = Map.get(levels, name, 0)
        levels = Map.put(levels, name, level)

        graph
        |> Multigraph.out_neighbors(name)
        |> Enum.reduce(levels, fn dependent, levels ->
          Map.update(levels, dependent, level + 1, &max(&1, level + 1))
        end)
      end)

    remaining = blocked |> Enum.filter(&Map.has_key?(components, &1)) |> Enum.sort()

    ordered =
      if remaining == [] do
        Enum.sort_by(components, fn {name, _node} -> {Map.fetch!(levels, name), name} end)
      end

    terminals =
      components
      |> Map.keys()
      |> Enum.filter(&(Multigraph.out_neighbors(graph, &1) == []))
      |> Enum.sort()

    %{
      levels: levels,
      remaining: remaining,
      ordered: ordered,
      dependencies: dependencies,
      terminals: terminals
    }
  end

  @doc false
  @spec needs(Component.component_node()) :: [String.t()]
  def needs(%{needs: needs}), do: needs

  @doc false
  @spec reference_dependencies(Component.component_node()) :: [String.t()]
  def reference_dependencies(node) do
    node
    |> Component.values()
    |> Enum.flat_map(&Value.result_refs/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc false
  @spec effective_dependencies(Component.component_node()) :: [String.t()]
  def effective_dependencies(node),
    do: (needs(node) ++ reference_dependencies(node)) |> Enum.uniq() |> Enum.sort()

  defp dependency_graph(dependencies) do
    graph =
      Multigraph.new(vertex_identifier: &Function.identity/1)
      |> Multigraph.add_vertices(Map.keys(dependencies))

    Enum.reduce(dependencies, graph, fn {name, dependencies}, graph ->
      dependencies
      |> Enum.reduce(graph, fn dependency, graph ->
        Multigraph.add_edge(graph, dependency, name)
      end)
    end)
  end

  defp blocked_vertices(graph, components) do
    cycles =
      graph
      |> Multigraph.strong_components()
      |> Enum.flat_map(fn
        [name] -> if name in Multigraph.out_neighbors(graph, name), do: [name], else: []
        names -> names
      end)

    missing = graph |> Multigraph.vertices() |> Enum.reject(&Map.has_key?(components, &1))
    Multigraph.reachable(graph, cycles ++ missing)
  end
end
