defmodule Jido.Topology.Composition do
  @moduledoc false
  alias Jido.Agent.Authoring
  alias Jido.Topology.{Ref, Reference, Validation}

  def validate(definition) do
    with {:ok, _} <- flatten(definition), do: :ok
  end

  def flatten(definition) do
    scopes = scopes(definition, [], %{})

    with :ok <- scope_limit(scopes),
         :ok <- validate_bindings(scopes),
         {:ok, collections} <-
           Authoring.traverse(Enum.sort(scopes), fn {path, context} ->
             nodes(context.definition, path, scopes)
           end),
         nodes = List.flatten(collections),
         {:ok, nodes} <- relationships(nodes, scopes),
         {:ok, nodes} <- connections(nodes, scopes),
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
    prefix = Enum.map_join(path, "", &("component/" <> escape(&1) <> "/"))
    prefix <> Atom.to_string(kind) <> "/" <> escape(key)
  end

  def escape(value), do: URI.encode(to_string(value), &URI.char_unreserved?/1)

  defp scopes(definition, path, acc) do
    acc = Map.put(acc, path, %{definition: definition, bindings: %{}})

    Enum.reduce(definition.includes, acc, fn include, acc ->
      child_path = path ++ [include.key]
      acc = scopes(include.topology, child_path, acc)
      bindings = Map.new(include.bindings, &{&1.key, %{path: path, target: &1.to}})
      Map.update!(acc, child_path, &Map.put(&1, :bindings, bindings))
    end)
  end

  defp scope_limit(scopes) when map_size(scopes) <= 1_000, do: :ok
  defp scope_limit(_), do: Authoring.error("Topology exceeds 1000 component scopes")

  defp validate_bindings(scopes) do
    Enum.reduce_while(scopes, :ok, fn
      {[], _}, :ok ->
        {:cont, :ok}

      {path, context}, :ok ->
        required = Enum.map(context.definition.imports, & &1.key) |> Enum.sort()
        supplied = Map.keys(context.bindings) |> Enum.sort()

        if required == supplied do
          case Authoring.traverse(required, &endpoint(scopes, path, &1, [])) do
            {:ok, _} -> {:cont, :ok}
            error -> {:halt, error}
          end
        else
          {:halt,
           Authoring.error("Import bindings must match the child requirements", %{
             path: path,
             required: required,
             supplied: supplied
           })}
        end
    end)
  end

  defp nodes(definition, path, scopes) do
    specifications =
      Enum.flat_map(
        [{:agent, definition.agents}, {:group, definition.groups}, {:bus, definition.resources}],
        fn {kind, values} ->
          Enum.map(values, &{kind, &1})
        end
      )

    Authoring.traverse(specifications, fn {kind, spec} ->
      with {:ok, deps} <-
             Authoring.traverse(Map.get(spec, :depends_on, []), &endpoint(scopes, path, &1, [])) do
        {:ok,
         Map.merge(spec, %{
           key: address(path, kind, spec.key),
           local: spec.key,
           scope: path,
           kind: kind,
           depends_on: Enum.map(deps, & &1.key),
           parent: nil,
           on_parent_exit: :stop,
           subscriptions: []
         })}
      end
    end)
  end

  defp relationships(nodes, scopes) do
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
      if length(records) == map_size(Map.new(records)) do
        owners = Map.new(records)

        {:ok,
         Enum.map(nodes, fn node ->
           case Map.get(owners, node.key) do
             nil ->
               node

             owner ->
               %{
                 node
                 | parent: owner.parent,
                   on_parent_exit: owner.policy,
                   depends_on: Enum.uniq([owner.parent | node.depends_on])
               }
           end
         end)}
      else
        Authoring.error("Each Agent or group can have only one owner")
      end
    end
  end

  defp connections(nodes, scopes) do
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
      if length(records) == length(Enum.uniq(records)) do
        connections = Enum.group_by(records, &elem(&1, 0), &elem(&1, 1))

        {:ok,
         Enum.map(nodes, fn node ->
           subscriptions = Map.get(connections, node.key, [])

           %{
             node
             | subscriptions: subscriptions,
               depends_on: Enum.uniq(node.depends_on ++ Enum.map(subscriptions, & &1.bus))
           }
         end)}
      else
        Authoring.error("Duplicate Bus subscription")
      end
    end
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
         {:ok, export} <-
           find(context.definition.exports, key, "Unknown topology export", child_path),
         {:ok, target} <- endpoint(scopes, child_path, export.from, seen),
         :ok <- kind(target, [export.kind]),
         do: {:ok, target}
  end

  defp resolve(scopes, path, name, seen) do
    context = Map.fetch!(scopes, path)
    definition = context.definition

    source =
      Enum.find_value(
        [
          {:agent, definition.agents},
          {:group, definition.groups},
          {:bus, definition.resources},
          {:import, definition.imports}
        ],
        fn {kind, values} ->
          if Enum.any?(values, &(&1.key == name)), do: kind
        end
      )

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
    Enum.reduce_while(scopes, :ok, fn {path, context}, :ok ->
      case Authoring.traverse(context.definition.exports, fn export ->
             with {:ok, target} <- endpoint(scopes, path, export.from, []),
                  :ok <- kind(target, [export.kind]),
                  do: {:ok, target}
           end) do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
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
    edges = Map.new(nodes, &{&1.key, &1.depends_on})

    edges =
      Enum.reduce(nodes, edges, fn node, edges ->
        Enum.reduce(node.depends_on, edges, fn key, edges ->
          if String.starts_with?(key, "import/"), do: Map.put_new(edges, key, []), else: edges
        end)
      end)

    case Validation.layers(edges) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp fetch_scope(scopes, path) do
    case Map.fetch(scopes, path) do
      {:ok, value} -> {:ok, value}
      :error -> Authoring.error("Unknown included topology", %{path: path})
    end
  end

  defp find(values, key, message, path) do
    case Enum.find(values, &(&1.key == key)) do
      nil -> Authoring.error(message, %{path: path, key: key})
      value -> {:ok, value}
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
