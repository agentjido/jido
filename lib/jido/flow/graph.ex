defmodule Jido.Flow.Graph do
  @moduledoc """
  Holds the derived dependencies for one canonical Flow.

  Every vertex is the string ID of one named Flow form. Compound form details
  and execution state do not become graph vertices. A Flow rebuilds this data
  from its forms and explicit needs. Stored Flow documents do not encode it.
  """

  @type id :: String.t()
  @type dependency_info :: %{data: [id()], control: [id()]}
  @type t :: %__MODULE__{dependencies: %{required(id()) => dependency_info()}}

  @enforce_keys [:dependencies]
  defstruct dependencies: %{}

  @doc false
  @spec build(map(), map()) :: {:ok, t()} | {:error, Exception.t()}
  def build(forms, needs) when is_map(forms) and is_map(needs) do
    ids = Map.keys(forms) |> MapSet.new()

    with :ok <- validate_need_owners(needs, ids),
         {:ok, dependencies} <- dependencies(forms, needs, ids),
         :ok <- acyclic(ids, dependencies) do
      {:ok, %__MODULE__{dependencies: dependencies}}
    end
  end

  defp validate_need_owners(needs, ids) do
    case needs |> Map.keys() |> Enum.sort() |> Enum.find(&(not MapSet.member?(ids, &1))) do
      nil -> :ok
      id -> failure("Flow needs contains an unknown form", :unknown_form, form: id)
    end
  end

  defp dependencies(forms, needs, ids) do
    forms
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce_while({:ok, %{}}, fn {target, form}, {:ok, result} ->
      data = form |> Jido.Flow.Form.result_refs() |> Enum.uniq() |> Enum.sort()
      control = needs |> Map.get(target, []) |> Enum.reject(&(&1 in data)) |> Enum.sort()

      case Enum.find(data ++ control, &(not MapSet.member?(ids, &1))) do
        nil ->
          {:cont, {:ok, Map.put(result, target, %{data: data, control: control})}}

        source ->
          {:halt,
           failure("Flow dependency points to an unknown form", :unknown_dependency,
             source: source,
             target: target
           )}
      end
    end)
  end

  defp acyclic(ids, dependencies) do
    indegrees = Map.new(ids, &{&1, 0})
    adjacency = Map.new(ids, &{&1, []})

    {indegrees, adjacency} =
      Enum.reduce(dependencies, {indegrees, adjacency}, fn {target,
                                                            %{data: data, control: control}},
                                                           {indegrees, adjacency} ->
        Enum.reduce(data ++ control, {indegrees, adjacency}, fn source, {indegrees, adjacency} ->
          {
            Map.update!(indegrees, target, &(&1 + 1)),
            Map.update!(adjacency, source, &[target | &1])
          }
        end)
      end)

    ready =
      indegrees
      |> Enum.flat_map(fn
        {id, 0} -> [id]
        {_id, _degree} -> []
      end)
      |> :gb_sets.from_list()

    {visited, indegrees} = visit(ready, adjacency, indegrees, 0)

    if visited == map_size(indegrees) do
      :ok
    else
      forms = cycle_members(ids, adjacency)
      failure("Flow dependency graph contains a cycle", :cycle, forms: Enum.sort(forms))
    end
  end

  defp cycle_members(ids, adjacency) do
    initial = %{
      index: 0,
      indices: %{},
      lowlinks: %{},
      stack: [],
      on_stack: MapSet.new(),
      members: MapSet.new()
    }

    ids
    |> Enum.sort()
    |> Enum.reduce(initial, fn id, state ->
      if Map.has_key?(state.indices, id), do: state, else: strong_connect(id, adjacency, state)
    end)
    |> Map.fetch!(:members)
    |> MapSet.to_list()
  end

  defp strong_connect(vertex, adjacency, state) do
    index = state.index

    state = %{
      state
      | index: index + 1,
        indices: Map.put(state.indices, vertex, index),
        lowlinks: Map.put(state.lowlinks, vertex, index),
        stack: [vertex | state.stack],
        on_stack: MapSet.put(state.on_stack, vertex)
    }

    state =
      adjacency
      |> Map.fetch!(vertex)
      |> Enum.reduce(state, fn target, state ->
        cond do
          not Map.has_key?(state.indices, target) ->
            state = strong_connect(target, adjacency, state)
            put_lowlink(state, vertex, Map.fetch!(state.lowlinks, target))

          MapSet.member?(state.on_stack, target) ->
            put_lowlink(state, vertex, Map.fetch!(state.indices, target))

          true ->
            state
        end
      end)

    if Map.fetch!(state.lowlinks, vertex) == Map.fetch!(state.indices, vertex) do
      {component, state} = pop_component(vertex, state, [])

      cyclic? =
        length(component) > 1 or
          (component == [vertex] and vertex in Map.fetch!(adjacency, vertex))

      if cyclic?,
        do: %{state | members: Enum.reduce(component, state.members, &MapSet.put(&2, &1))},
        else: state
    else
      state
    end
  end

  defp put_lowlink(state, vertex, candidate) do
    lowlink = min(Map.fetch!(state.lowlinks, vertex), candidate)
    %{state | lowlinks: Map.put(state.lowlinks, vertex, lowlink)}
  end

  defp pop_component(vertex, %{stack: [current | rest]} = state, component) do
    state = %{state | stack: rest, on_stack: MapSet.delete(state.on_stack, current)}
    component = [current | component]

    if current == vertex,
      do: {component, state},
      else: pop_component(vertex, state, component)
  end

  defp visit(ready, adjacency, indegrees, visited) do
    if :gb_sets.is_empty(ready) do
      {visited, indegrees}
    else
      {id, ready} = :gb_sets.take_smallest(ready)

      {indegrees, ready} =
        adjacency
        |> Map.fetch!(id)
        |> Enum.reduce({indegrees, ready}, fn target, {indegrees, ready} ->
          indegrees = Map.update!(indegrees, target, &(&1 - 1))

          ready =
            if Map.fetch!(indegrees, target) == 0,
              do: :gb_sets.add(target, ready),
              else: ready

          {indegrees, ready}
        end)

      visit(ready, adjacency, indegrees, visited + 1)
    end
  end

  defp failure(message, reason, details) do
    {:error, Jido.Flow.Error.validation_error(message, Map.new([reason: reason] ++ details))}
  end
end
