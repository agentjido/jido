defmodule Jido.Flow.Graph do
  @moduledoc false

  alias Jido.Flow.Definition

  @type analysis :: %{
          levels: %{optional(String.t()) => non_neg_integer()},
          remaining: [String.t()],
          ordered: [Definition.named_component()] | nil,
          dependencies: %{optional(String.t()) => [String.t()]},
          terminals: [String.t()]
        }

  @doc false
  @spec canonical_components(Definition.components()) :: [Definition.named_component()]
  def canonical_components(components) when is_map(components) do
    %{ordered: ordered, remaining: []} = analyze(components)
    ordered
  end

  @doc false
  @spec analyze(Definition.components()) :: analysis()
  def analyze(components) when is_map(components) do
    dependencies =
      Map.new(components, fn {name, node} -> {name, Definition.effective_dependencies(node)} end)

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
