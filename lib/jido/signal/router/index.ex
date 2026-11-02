defmodule Jido.Signal.Router.Index do
  @moduledoc false

  alias Jido.Signal.Router.{Route, Router}

  @doc false
  @spec new([Route.t()]) :: Router.t()
  def new(routes) do
    {entries, next_order} = compile_entries(routes, 0)
    router = %Router{}

    {exact_index, wildcard_index, next_node_id} =
      index_entries(entries, router.exact_index, router.wildcard_index, router.next_node_id)

    %Router{
      entries: entries,
      exact_index: exact_index,
      wildcard_index: wildcard_index,
      next_order: next_order,
      next_node_id: next_node_id
    }
  end

  @doc false
  @spec add(Router.t(), [Route.t()]) :: Router.t()
  def add(%Router{} = router, routes) do
    {new_entries, next_order} = compile_entries(routes, router.next_order)

    {exact_index, wildcard_index, next_node_id} =
      index_entries(
        new_entries,
        router.exact_index,
        router.wildcard_index,
        router.next_node_id
      )

    %{
      router
      | entries: router.entries ++ new_entries,
        exact_index: exact_index,
        wildcard_index: wildcard_index,
        next_order: next_order,
        next_node_id: next_node_id
    }
  end

  @doc false
  @spec remove(Router.t(), [String.t()]) :: Router.t()
  def remove(%Router{} = router, paths) do
    paths = MapSet.new(paths)
    entries = Enum.reject(router.entries, &MapSet.member?(paths, &1.route.path))

    {exact_index, wildcard_index} =
      Enum.reduce(paths, {router.exact_index, router.wildcard_index}, fn path,
                                                                         {exact, wildcard} ->
        if wildcard_path?(path) do
          {exact, delete_trie_path(wildcard, String.split(path, "."))}
        else
          {Map.delete(exact, path), wildcard}
        end
      end)

    %{router | entries: entries, exact_index: exact_index, wildcard_index: wildcard_index}
  end

  @doc false
  @spec remove_target(Router.t(), String.t(), term()) :: Router.t()
  def remove_target(%Router{} = router, path, target) do
    reject = fn entries ->
      Enum.reject(entries, &(&1.route.path == path and &1.route.target == target))
    end

    {exact_index, wildcard_index} =
      if wildcard_path?(path) do
        {router.exact_index,
         delete_trie_path(router.wildcard_index, String.split(path, "."), reject)}
      else
        exact =
          case reject.(Map.get(router.exact_index, path, [])) do
            [] -> Map.delete(router.exact_index, path)
            entries -> Map.put(router.exact_index, path, entries)
          end

        {exact, router.wildcard_index}
      end

    %{
      router
      | entries: reject.(router.entries),
        exact_index: exact_index,
        wildcard_index: wildcard_index
    }
  end

  @doc false
  @spec lookup(Router.t(), String.t(), Jido.Signal.t()) :: [term()]
  def lookup(%Router{} = router, type, signal) do
    (Map.get(router.exact_index, type, []) ++
       wildcard_matches(router.wildcard_index, type))
    |> Enum.filter(&predicate_matches?(&1.route.match, signal))
    |> Enum.sort_by(&precedence_key/1, :desc)
    |> Enum.flat_map(&targets/1)
  end

  @doc false
  @spec matches?(String.t(), String.t()) :: boolean()
  def matches?(type, pattern) do
    match_segments?(String.split(type, "."), String.split(pattern, "."))
  end

  @doc false
  @spec compile_pattern(String.t()) :: String.t() | tuple()
  def compile_pattern(pattern) do
    if wildcard_path?(pattern),
      do: pattern |> String.split(".") |> List.to_tuple(),
      else: pattern
  end

  @doc false
  @spec matches_compiled?(String.t(), String.t() | tuple()) :: boolean()
  def matches_compiled?(type, pattern) when is_binary(pattern), do: type == pattern

  def matches_compiled?(type, pattern) when is_tuple(pattern) do
    match_tuples?(type |> String.split(".") |> List.to_tuple(), pattern)
  end

  @doc false
  @spec has_route?(Router.t(), String.t()) :: boolean()
  def has_route?(%Router{} = router, path) do
    if wildcard_path?(path) do
      trie_has_path?(router.wildcard_index, String.split(path, "."))
    else
      Map.has_key?(router.exact_index, path)
    end
  end

  defp compile_entries(routes, first_order) do
    Enum.map_reduce(routes, first_order, fn route, order ->
      segments = String.split(route.path, ".")

      entry = %{
        route: route,
        segments: segments,
        class: pattern_class(segments),
        complexity: pattern_complexity(segments),
        order: order
      }

      {entry, order + 1}
    end)
  end

  defp index_entries(entries, exact_index, wildcard_index, next_node_id) do
    Enum.reduce(
      entries,
      {exact_index, wildcard_index, next_node_id},
      fn entry, {exact, wildcard, node_id} ->
        if entry.class == 2 do
          {Map.update(exact, entry.route.path, [entry], &[entry | &1]), wildcard, node_id}
        else
          {wildcard, node_id} = insert_trie(wildcard, entry.segments, entry, node_id)
          {exact, wildcard, node_id}
        end
      end
    )
  end

  defp insert_trie(node, [], entry, next_node_id) do
    {%{node | terminals: [entry | node.terminals]}, next_node_id}
  end

  defp insert_trie(node, [segment | rest], entry, next_node_id) do
    {child, next_node_id} = trie_child(node, segment, next_node_id)
    {child, next_node_id} = insert_trie(child, rest, entry, next_node_id)
    {put_trie_child(node, segment, child), next_node_id}
  end

  defp trie_child(node, "*", next_node_id),
    do: existing_or_new_node(node.single, next_node_id, false)

  defp trie_child(node, "**", next_node_id),
    do: existing_or_new_node(node.multi, next_node_id, true)

  defp trie_child(node, segment, next_node_id),
    do: existing_or_new_node(Map.get(node.exact, segment), next_node_id, false)

  defp existing_or_new_node(nil, next_node_id, globstar?) do
    {new_trie_node(next_node_id, globstar?), next_node_id + 1}
  end

  defp existing_or_new_node(node, next_node_id, _globstar?), do: {node, next_node_id}

  defp new_trie_node(id, globstar?) do
    %{
      id: id,
      exact: %{},
      single: nil,
      multi: nil,
      terminals: [],
      globstar?: globstar?
    }
  end

  defp put_trie_child(node, "*", child), do: %{node | single: child}
  defp put_trie_child(node, "**", child), do: %{node | multi: child}

  defp put_trie_child(node, segment, child) do
    %{node | exact: Map.put(node.exact, segment, child)}
  end

  defp wildcard_matches(
         %{exact: exact, single: nil, multi: nil, terminals: []},
         _type
       )
       when map_size(exact) == 0,
       do: []

  defp wildcard_matches(root, type) do
    segments = type |> String.split(".") |> List.to_tuple()
    {_visited, matches} = walk_trie(root, segments, tuple_size(segments), 0, %{}, [])
    matches
  end

  defp walk_trie(node, segments, segment_count, position, visited, matches) do
    state = {node.id, position}

    if Map.has_key?(visited, state) do
      {visited, matches}
    else
      visited = Map.put(visited, state, true)
      matches = if position == segment_count, do: node.terminals ++ matches, else: matches

      {visited, matches} =
        walk_segment_children(node, segments, segment_count, position, visited, matches)

      {visited, matches} =
        case node.multi do
          nil -> {visited, matches}
          child -> walk_trie(child, segments, segment_count, position, visited, matches)
        end

      if node.globstar? and position < segment_count do
        walk_trie(node, segments, segment_count, position + 1, visited, matches)
      else
        {visited, matches}
      end
    end
  end

  defp walk_segment_children(node, segments, segment_count, position, visited, matches)
       when position < segment_count do
    segment = elem(segments, position)

    {visited, matches} =
      case Map.get(node.exact, segment) do
        nil -> {visited, matches}
        child -> walk_trie(child, segments, segment_count, position + 1, visited, matches)
      end

    case node.single do
      nil -> {visited, matches}
      child -> walk_trie(child, segments, segment_count, position + 1, visited, matches)
    end
  end

  defp walk_segment_children(
         _node,
         _segments,
         _segment_count,
         _position,
         visited,
         matches
       ),
       do: {visited, matches}

  defp delete_trie_path(node, segments), do: delete_trie_path(node, segments, fn _ -> [] end)

  defp delete_trie_path(node, [], reject), do: %{node | terminals: reject.(node.terminals)}

  defp delete_trie_path(node, [segment | rest], reject) do
    case get_trie_child(node, segment) do
      nil ->
        node

      child ->
        child = delete_trie_path(child, rest, reject)
        put_or_delete_trie_child(node, segment, child)
    end
  end

  defp get_trie_child(node, "*"), do: node.single
  defp get_trie_child(node, "**"), do: node.multi
  defp get_trie_child(node, segment), do: Map.get(node.exact, segment)

  defp put_or_delete_trie_child(node, segment, child) do
    if empty_trie_node?(child) do
      delete_trie_child(node, segment)
    else
      put_trie_child(node, segment, child)
    end
  end

  defp delete_trie_child(node, "*"), do: %{node | single: nil}
  defp delete_trie_child(node, "**"), do: %{node | multi: nil}
  defp delete_trie_child(node, segment), do: %{node | exact: Map.delete(node.exact, segment)}

  defp empty_trie_node?(node) do
    node.terminals == [] and node.single == nil and node.multi == nil and
      map_size(node.exact) == 0
  end

  defp trie_has_path?(node, []), do: node.terminals != []

  defp trie_has_path?(node, [segment | rest]) do
    case get_trie_child(node, segment) do
      nil -> false
      child -> trie_has_path?(child, rest)
    end
  end

  defp wildcard_path?(path), do: String.contains?(path, "*")

  defp pattern_class(segments) do
    cond do
      "**" in segments -> 0
      "*" in segments -> 1
      true -> 2
    end
  end

  defp pattern_complexity(segments) do
    length = length(segments)
    pattern_complexity(segments, length, 0, length * 2000)
  end

  defp pattern_complexity([], _length, _index, score), do: score

  defp pattern_complexity(["*" | rest], length, index, score),
    do: pattern_complexity(rest, length, index + 1, score - 1000 + index * 100)

  defp pattern_complexity(["**" | rest], length, index, score),
    do: pattern_complexity(rest, length, index + 1, score - 2000 + index * 200)

  defp pattern_complexity([_segment | rest], length, index, score),
    do: pattern_complexity(rest, length, index + 1, score + 3000 * (length - index))

  defp precedence_key(entry) do
    {entry.class, entry.complexity, entry.route.priority, -entry.order}
  end

  defp predicate_matches?(match, signal) do
    Route.matched?(match, signal)
  rescue
    _error -> false
  catch
    _kind, _reason -> false
  end

  defp targets(%{route: %Route{target: targets}})
       when is_list(targets) and is_integer(length(targets)),
       do: targets

  defp targets(%{route: %Route{target: target}}), do: [target]

  defp match_segments?(type_segments, pattern_segments) do
    match_tuples?(List.to_tuple(type_segments), List.to_tuple(pattern_segments))
  end

  defp match_tuples?(type_segments, pattern_segments) do
    do_match_segments(
      type_segments,
      pattern_segments,
      tuple_size(type_segments),
      tuple_size(pattern_segments),
      0,
      0,
      nil,
      nil
    )
  end

  defp do_match_segments(type, pattern, type_size, pattern_size, i, j, star_i, star_j) do
    cond do
      j < pattern_size and elem(pattern, j) == "**" ->
        do_match_segments(type, pattern, type_size, pattern_size, i, j + 1, i, j + 1)

      i < type_size and j < pattern_size and
          segment_matches?(elem(type, i), elem(pattern, j)) ->
        do_match_segments(type, pattern, type_size, pattern_size, i + 1, j + 1, star_i, star_j)

      i == type_size ->
        remaining_multi_wildcards?(pattern, j, pattern_size)

      not is_nil(star_j) and star_i < type_size ->
        next_i = star_i + 1
        do_match_segments(type, pattern, type_size, pattern_size, next_i, star_j, next_i, star_j)

      true ->
        false
    end
  end

  defp segment_matches?(type_segment, pattern_segment),
    do: pattern_segment == "*" or pattern_segment == type_segment

  defp remaining_multi_wildcards?(_pattern, index, size) when index == size, do: true

  defp remaining_multi_wildcards?(pattern, index, size) do
    elem(pattern, index) == "**" and remaining_multi_wildcards?(pattern, index + 1, size)
  end
end
