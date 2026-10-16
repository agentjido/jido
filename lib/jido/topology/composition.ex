defmodule Jido.Topology.Composition do
  @moduledoc false
  alias Jido.Agent.Authoring
  alias Jido.Topology.{Ref, Reference, Validation}

  def flatten(definition) do
    with {:ok, scopes} <- scopes(definition, [], %{}, %{}),
         :ok <- validate_bindings(scopes),
         {:ok, collections} <-
           Authoring.traverse(Enum.sort(scopes), fn {path, context} ->
             nodes(context.definition, path, scopes)
           end),
         nodes = List.flatten(collections),
         {:ok, owners} <- relationships(scopes),
         {:ok, subscriptions} <- connections(scopes),
         nodes = Enum.map(nodes, &graph_metadata(&1, owners, subscriptions)),
         {:ok, lookup} <- lookup(scopes),
         :ok <- validate_exports(scopes),
         :ok <- graph(nodes) do
      {:ok, %{nodes: nodes, scopes: scopes, lookup: lookup}}
    end
  end

  def inputs(definition, input), do: inputs(definition, input, [], %{})

  defp inputs(definition, input, path, acc) do
    Enum.reduce_while(definition.includes, {:ok, Map.put(acc, path, input)}, fn include,
                                                                                {:ok, acc} ->
      with {:ok, mapped} <- Reference.resolve(include.inputs, input),
           {:ok, child_input} <- Validation.parse_input(include.topology.schema, mapped),
           {:ok, acc} <- inputs(include.topology, child_input, path ++ [include.key], acc) do
        {:cont, {:ok, acc}}
      else
        {:error, error} ->
          {:halt,
           Authoring.error("Invalid included topology input", %{
             path: path ++ [include.key],
             cause: error
           })}
      end
    end)
  end

  def address(path, kind, key) do
    prefix = Enum.map_join(path, &("component/" <> escape(&1) <> "/"))
    prefix <> Atom.to_string(kind) <> "/" <> escape(key)
  end

  def escape(value), do: URI.encode(to_string(value), &URI.char_unreserved?/1)

  defp scopes(_definition, _path, _bindings, acc) when map_size(acc) >= 1_000,
    do: Authoring.error("Topology exceeds 1000 component scopes")

  defp scopes(definition, path, bindings, acc) do
    context = %{
      definition: definition,
      bindings: bindings,
      endpoints: endpoint_index(definition),
      exports: Map.new(definition.exports, &{&1.key, &1})
    }

    acc = Map.put(acc, path, context)

    Enum.reduce_while(definition.includes, {:ok, acc}, fn include, {:ok, acc} ->
      child_path = path ++ [include.key]
      bindings = Map.new(include.bindings, &{&1.key, %{path: path, target: &1.to}})

      case scopes(include.topology, child_path, bindings, acc) do
        {:ok, acc} ->
          {:cont, {:ok, acc}}

        {:error, _error} = error ->
          {:halt, error}
      end
    end)
  end

  defp endpoint_index(definition) do
    [
      {:agent, definition.agents},
      {:group, definition.groups},
      {:resource, definition.resources},
      {:import, definition.imports}
    ]
    |> Enum.flat_map(fn
      {:resource, entries} -> Enum.map(entries, &{&1.key, &1.kind})
      {kind, entries} -> Enum.map(entries, &{&1.key, kind})
    end)
    |> Map.new()
  end

  defp validate_bindings(scopes) do
    Authoring.check_each(scopes, fn
      {[], _} ->
        :ok

      {path, context} ->
        required = Enum.map(context.definition.imports, & &1.key) |> Enum.sort()
        supplied = Map.keys(context.bindings) |> Enum.sort()

        if required == supplied do
          Authoring.check_each(required, fn key ->
            with {:ok, _} <- endpoint(scopes, path, key, []), do: :ok
          end)
        else
          Authoring.error("Import bindings must match the child requirements", %{
            path: path,
            required: required,
            supplied: supplied
          })
        end
    end)
  end

  defp nodes(definition, path, scopes) do
    specifications =
      Enum.flat_map(
        [{:agent, definition.agents}, {:group, definition.groups}],
        fn {kind, values} -> Enum.map(values, &{kind, &1}) end
      ) ++
        Enum.map(definition.resources, &{&1.kind, &1})

    Authoring.traverse(specifications, fn {kind, spec} ->
      with {:ok, deps} <-
             Authoring.traverse(Map.get(spec, :depends_on, []), &endpoint(scopes, path, &1, [])) do
        {:ok,
         Map.merge(spec, %{
           key: address(path, kind, spec.key),
           local: spec.key,
           scope: path,
           kind: kind,
           depends_on: Enum.map(deps, & &1.key)
         })}
      end
    end)
  end

  defp relationships(scopes) do
    records =
      Enum.flat_map(Enum.sort(scopes), fn {path, context} ->
        Enum.map(context.definition.relationships, &{path, &1})
      end)

    with {:ok, records} <-
           Authoring.traverse(records, fn {path, edge} ->
             with {:ok, parent} <- endpoint(scopes, path, edge.parent, []),
                  :ok <- kind(parent, [:agent]),
                  {:ok, child} <- endpoint(scopes, path, edge.child, []),
                  :ok <- kind(child, [:agent, :group]),
                  do: {:ok, {child.key, %{parent: parent.key, policy: edge.on_parent_exit}}}
           end) do
      owners = Map.new(records)

      if length(records) == map_size(owners),
        do: {:ok, owners},
        else: Authoring.error("Each Agent or group can have only one owner")
    end
  end

  defp connections(scopes) do
    records =
      Enum.flat_map(Enum.sort(scopes), fn {path, context} ->
        Enum.map(context.definition.connections, &{path, &1})
      end)

    with {:ok, records} <-
           Authoring.traverse(records, fn {path, edge} ->
             with {:ok, agent} <- endpoint(scopes, path, edge.agent, []),
                  :ok <- kind(agent, [:agent, :group]),
                  {:ok, bus} <- endpoint(scopes, path, edge.to, []),
                  :ok <- kind(bus, [:bus]),
                  do: {:ok, {agent.key, %{bus: bus.key, path: edge.path}}}
           end) do
      if length(records) == length(Enum.uniq(records)),
        do: {:ok, Enum.group_by(records, &elem(&1, 0), &elem(&1, 1))},
        else: Authoring.error("Duplicate Bus subscription")
    end
  end

  defp graph_metadata(node, owners, connections) do
    owner = Map.get(owners, node.key, %{})
    parent = Map.get(owner, :parent)
    subscriptions = Map.get(connections, node.key, [])

    Map.merge(node, %{
      parent: parent,
      on_parent_exit: Map.get(owner, :policy, :stop),
      subscriptions: subscriptions,
      depends_on:
        Enum.uniq(List.wrap(parent) ++ node.depends_on ++ Enum.map(subscriptions, & &1.bus))
    })
  end

  defp endpoint(scopes, path, target, seen) do
    token = {path, target}

    if token in seen do
      Authoring.error("Topology export or binding cycle", %{path: path, target: target})
    else
      resolve(scopes, path, target, [token | seen])
    end
  end

  defp resolve(scopes, path, %Ref{component: component, key: key}, seen) do
    child_path = path ++ [component]

    with {:ok, context} <- fetch_scope(scopes, child_path),
         {:ok, export} <- fetch_export(context, key, child_path),
         {:ok, target} <- endpoint(scopes, child_path, export.from, seen),
         :ok <- kind(target, [export.kind]),
         do: {:ok, target}
  end

  defp resolve(scopes, path, name, seen) do
    context = Map.fetch!(scopes, path)
    source = Map.get(context.endpoints, name)

    case source do
      nil -> Authoring.error("Unknown topology endpoint", %{path: path, key: name})
      :import -> resolve_import(scopes, path, name, context, seen)
      kind -> {:ok, %{kind: kind, key: address(path, kind, name)}}
    end
  end

  defp resolve_import(_scopes, [], name, _context, _seen),
    do: {:ok, %{kind: :bus, key: address([], :import, name)}}

  defp resolve_import(scopes, path, name, context, seen) do
    case Map.fetch(context.bindings, name) do
      {:ok, binding} ->
        with {:ok, target} <- endpoint(scopes, binding.path, binding.target, seen),
             :ok <- kind(target, [:bus]),
             do: {:ok, target}

      :error ->
        Authoring.error("Missing topology import binding", %{path: path, key: name})
    end
  end

  defp validate_exports(scopes) do
    Authoring.check_each(scopes, fn {path, context} ->
      Authoring.check_each(context.definition.exports, fn export ->
        with {:ok, target} <- endpoint(scopes, path, export.from, []),
             do: kind(target, [export.kind])
      end)
    end)
  end

  defp lookup(scopes) do
    root = Map.fetch!(scopes, []).definition
    locals = root.agents ++ root.groups ++ root.resources

    exports =
      Enum.flat_map(root.includes, fn include ->
        Enum.map(include.topology.exports, &%Ref{component: include.key, key: &1.key})
      end)

    with {:ok, pairs} <-
           Authoring.traverse(Enum.map(locals, & &1.key) ++ exports, fn key ->
             with {:ok, target} <- endpoint(scopes, [], key, []), do: {:ok, {key, target}}
           end),
         do: {:ok, Map.new(pairs)}
  end

  defp graph(nodes) do
    edges =
      Enum.reduce(nodes, %{}, fn node, edges ->
        edges = Map.put(edges, node.key, node.depends_on)

        Enum.reduce(node.depends_on, edges, fn key, edges ->
          if String.starts_with?(key, "import/"), do: Map.put_new(edges, key, []), else: edges
        end)
      end)

    with {:ok, _} <- Validation.layers(edges), do: :ok
  end

  defp fetch_scope(scopes, path) do
    case Map.fetch(scopes, path) do
      {:ok, value} -> {:ok, value}
      :error -> Authoring.error("Unknown included topology", %{path: path})
    end
  end

  defp fetch_export(context, key, path) do
    case Map.fetch(context.exports, key) do
      {:ok, export} -> {:ok, export}
      :error -> Authoring.error("Unknown topology export", %{path: path, key: key})
    end
  end

  defp kind(target, allowed) do
    if target.kind in allowed,
      do: :ok,
      else:
        Authoring.error("Topology endpoint has the wrong kind", %{
          expected: allowed,
          actual: target.kind
        })
  end
end
