defmodule Jido.Topology.Validation do
  @moduledoc false
  alias Jido.Agent.Authoring
  alias Jido.Topology.{EntryMetadata, Ref, Reference, Resource}

  @fields [
    :name,
    :schema,
    :metadata,
    :agents,
    :groups,
    :resources,
    :relationships,
    :connections,
    :startup,
    :includes,
    :children,
    :imports,
    :exports
  ]

  def keys(attrs), do: Authoring.keys(attrs, @fields)

  def field(:name, value) do
    with {:ok, _} <- key(value), do: :ok
  end

  def field(:schema, %Zoi.Types.Map{} = schema), do: Jido.Agent.State.validate_schema(schema)
  def field(:schema, _), do: Authoring.error("Topology input schema must be a Zoi object")

  def field(:metadata, value) do
    with {:ok, _} <- plain_static_map(value), do: :ok
  end

  def field(_, _), do: :ok

  def definition(attrs, ancestors \\ [], depth \\ 0)

  def definition(_, _, depth) when depth > 32,
    do: Authoring.error("Topology depth exceeds 32")

  def definition(%Jido.Topology{} = attrs, ancestors, depth),
    do: definition(Map.from_struct(attrs), ancestors, depth)

  def definition(attrs, ancestors, depth) do
    with {:ok, attrs} <- Authoring.attrs(attrs),
         :ok <- Authoring.keys(attrs, @fields),
         {:ok, name} <- at(:name, key(Map.get(attrs, :name))),
         schema = Map.get(attrs, :schema, Zoi.object(%{})),
         :ok <- at(:schema, field(:schema, schema)),
         {:ok, metadata} <- at(:metadata, plain_static_map(Map.get(attrs, :metadata, %{}))),
         {:ok, agents} <- entries(attrs, :agents, :agent),
         {:ok, groups} <- entries(attrs, :groups, :group),
         {:ok, resources} <- entries(attrs, :resources, :resource),
         {:ok, relationships} <- entries(attrs, :relationships, :owns),
         {:ok, connections} <- entries(attrs, :connections, :subscribe),
         {:ok, startup} <- at(:startup, entry(:startup, Map.get(attrs, :startup, %{}))),
         {:ok, imports} <- entries(attrs, :imports, :import),
         {:ok, exports} <- entries(attrs, :exports, :export),
         {:ok, children} <-
           Authoring.traverse_indexed(
             Map.get(attrs, :children, []),
             &Jido.Topology.Child.normalize(&1, ancestors, depth)
           )
           |> Authoring.at(:children),
         {:ok, includes} <-
           Authoring.traverse_indexed(
             Map.get(attrs, :includes, []),
             &include(&1, ancestors, depth)
           )
           |> Authoring.at(:includes) do
      definition = %{
        name: name,
        schema: schema,
        metadata: metadata,
        agents: agents,
        groups: groups,
        resources: resources,
        relationships: relationships,
        connections: connections,
        startup: startup,
        imports: imports,
        exports: exports,
        includes: includes,
        children: children
      }

      with :ok <- names(definition), do: {:ok, definition}
    end
  end

  defp entries(attrs, field, kind),
    do:
      Authoring.traverse_indexed(Map.get(attrs, field, []), &entry(kind, &1))
      |> Authoring.at(field)

  def entry(kind, attrs) do
    with {:ok, attrs} <- Authoring.attrs(attrs),
         :ok <- entry_keys(attrs, kind),
         attrs = EntryMetadata.apply_defaults(kind, attrs),
         {:ok, value} <- normalize(kind, attrs),
         :ok <- static_entry(kind, value),
         do: {:ok, value}
  end

  defp entry_keys(attrs, kind) do
    case Authoring.keys(attrs, EntryMetadata.fields(kind)) do
      {:error, %{details: %{keys: [key | _]}}} = error -> at(key, error)
      result -> result
    end
  end

  defp static_entry(:include, _value), do: :ok

  defp static_entry(kind, value) do
    EntryMetadata.fields(kind)
    |> Enum.reject(&(&1 == :definition and kind in [:agent, :group]))
    |> Enum.reduce_while(:ok, fn field, :ok ->
      case at(field, static(Map.get(value, field))) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp normalize(kind, attrs) when kind in [:agent, :group] do
    with {:ok, name} <- at(:key, key(attrs[:key])),
         {:ok, selection} <- agent_selection(attrs),
         {:ok, state} <- at(:initial_state, initial_state(attrs.initial_state)),
         {:ok, deps} <-
           at(:depends_on, Authoring.traverse_indexed(attrs.depends_on, &Ref.target/1)),
         {:ok, placement} <- at(:node, placement(Map.get(attrs, :node))) do
      agent = %{
        key: name,
        initial_state: state,
        depends_on: deps,
        node: placement
      }

      agent = Map.merge(agent, selection)

      if kind == :agent, do: {:ok, agent}, else: group(agent, attrs)
    end
  end

  defp normalize(:resource, attrs) do
    with {:ok, name} <- at(:key, key(attrs[:key])),
         kind = attrs.kind,
         {:ok, config} <- resource_config(kind, attrs.config) do
      {:ok, %{key: name, kind: kind, config: config}}
    end
  end

  defp normalize(:owns, attrs) do
    with {:ok, parent} <- at(:parent, Ref.target(attrs[:parent])),
         {:ok, child} <- at(:child, Ref.target(attrs[:child])),
         policy = attrs.on_parent_exit,
         :ok <- one_of(policy, [:stop, :continue, :emit_orphan], :on_parent_exit) do
      {:ok, %{parent: parent, child: child, on_parent_exit: policy}}
    end
  end

  defp normalize(:subscribe, attrs) do
    with {:ok, agent} <- at(:agent, Ref.target(attrs[:agent])),
         {:ok, bus} <- at(:to, Ref.target(attrs[:to])),
         :ok <- at(:path, path(attrs[:path])) do
      {:ok, %{agent: agent, to: bus, path: attrs.path}}
    end
  end

  defp normalize(:startup, attrs) do
    with :ok <- positive(attrs.concurrency, :concurrency),
         :ok <- positive(attrs.max_agents, :max_agents),
         :ok <- positive(attrs.retry_interval, :retry_interval),
         :ok <- positive(attrs.task_timeout, :task_timeout),
         do: {:ok, attrs}
  end

  defp normalize(:import, attrs) do
    with {:ok, key} <- at(:key, key(attrs[:key])),
         :ok <- one_of(attrs[:kind], [:bus], :kind),
         do: {:ok, %{key: key, kind: :bus}}
  end

  defp normalize(:export, attrs) do
    with {:ok, key} <- at(:key, key(attrs[:key])),
         :ok <- one_of(attrs[:kind], [:agent, :group, :bus], :kind),
         {:ok, from} <- at(:from, Ref.target(attrs[:from])),
         do: {:ok, %{key: key, kind: attrs.kind, from: from}}
  end

  defp normalize(:binding, attrs) do
    with {:ok, key} <- at(:key, key(attrs[:key])),
         {:ok, to} <- at(:to, Ref.target(attrs[:to])),
         do: {:ok, %{key: key, to: to}}
  end

  defp normalize(:include, attrs), do: include(attrs, [], 0)

  defp resource_config(kind, config) do
    case Resource.validate(kind, config) do
      {:error, %{details: %{field: field}}} = error -> at(field, error)
      result -> at(:config, result)
    end
  end

  defp include(attrs, ancestors, depth) do
    with {:ok, attrs} <- Authoring.attrs(attrs),
         :ok <- entry_keys(attrs, :include),
         attrs = EntryMetadata.apply_defaults(:include, attrs),
         {:ok, key} <- at(:key, key(attrs[:key])),
         {:ok, source, ancestors} <- at(:topology, included_source(attrs[:topology], ancestors)),
         {:ok, definition} <- at(:topology, definition(source, ancestors, depth + 1)),
         :ok <- at(:topology, static_include(definition)),
         {:ok, inputs} <- at(:inputs, plain_static_map(attrs.inputs)),
         {:ok, bindings} <- at(:bindings, bindings(attrs.bindings)),
         :ok <- unique(Enum.map(bindings, & &1.key), "Duplicate import binding") do
      {:ok,
       %{
         key: key,
         topology: struct(Jido.Topology, definition),
         inputs: inputs,
         bindings: bindings
       }}
    end
  end

  defp included_source(module, ancestors) when is_atom(module) and not is_nil(module) do
    cond do
      module in ancestors ->
        Authoring.error("Recursive topology inclusion", %{module: module})

      Code.ensure_loaded?(module) and function_exported?(module, :__topology_config__, 0) ->
        {:ok, module.__topology_config__(), [module | ancestors]}

      true ->
        Authoring.error("Expected a topology module or definition")
    end
  rescue
    error -> source_error(module, :error, error)
  catch
    kind, reason -> source_error(module, kind, reason)
  end

  defp included_source(%Jido.Topology{} = value, ancestors), do: {:ok, value, ancestors}

  defp included_source(value, ancestors) when is_map(value) or is_list(value),
    do: {:ok, value, ancestors}

  defp included_source(_, _), do: Authoring.error("Expected a topology module or definition")

  def source_error(module, kind, reason),
    do:
      Authoring.error("Topology module configuration failed", %{
        module: module,
        kind: kind,
        reason: reason
      })

  defp static_include(%{children: []}), do: :ok
  defp static_include(_), do: Authoring.error("Static include cannot contain runtime children")

  defp bindings(value) when is_map(value) and not is_struct(value) do
    value |> Enum.sort() |> Enum.map(fn {key, to} -> %{key: key, to: to} end) |> bindings()
  end

  defp bindings(values), do: Authoring.traverse_indexed(values, &entry(:binding, &1))

  defp group(agent, %{members: members, key_by: key_by} = attrs) do
    cond do
      Map.has_key?(attrs, :count) ->
        at(:count, Authoring.error("A group uses count or members, not both"))

      not (is_atom(key_by) or is_binary(key_by)) ->
        at(:key_by, Authoring.error("Group key_by must name a member field"))

      not (is_list(members) or match?(%Reference{kind: :input}, members)) ->
        at(:members, Authoring.error("Group members must be a list or input reference"))

      true ->
        {:ok, Map.merge(agent, %{members: members, key_by: key_by})}
    end
  end

  defp group(agent, attrs) do
    count = Map.get(attrs, :count, EntryMetadata.default(:group, :count))

    cond do
      Map.has_key?(attrs, :members) or Map.has_key?(attrs, :key_by) ->
        at(:members, Authoring.error("A keyed group requires members and key_by"))

      is_integer(count) and count >= 0 ->
        {:ok, Map.put(agent, :count, count)}

      match?(%Reference{kind: :input}, count) ->
        {:ok, Map.put(agent, :count, count)}

      true ->
        at(:count, Authoring.error("Group count must be nonnegative or an input reference"))
    end
  end

  def key(value) when is_atom(value) and value not in [nil, true, false],
    do: key(Atom.to_string(value))

  def key(value) when is_binary(value) and byte_size(value) in 1..255 do
    if String.valid?(value), do: {:ok, value}, else: Authoring.error("Topology key must be UTF-8")
  end

  def key(_), do: Authoring.error("Topology keys must be nonempty strings or atoms")

  def parse_input(schema, input) when is_map(input) and not is_struct(input) do
    case Zoi.parse(schema, input) do
      {:ok, value} when is_map(value) and not is_struct(value) ->
        with :ok <- static(value), do: {:ok, value}

      {:error, errors} ->
        Authoring.error("Invalid topology input", %{errors: errors})

      _ ->
        Authoring.error("Topology input schema must produce a map")
    end
  end

  def parse_input(_, _), do: Authoring.error("Topology input must be a plain map")

  defp initial_state(%Reference{} = value), do: {:ok, value}
  defp initial_state(value), do: plain_static_map(value)

  defp placement(nil), do: {:ok, nil}
  defp placement(%Reference{} = value), do: {:ok, value}

  defp placement(value) when is_atom(value) and value not in [true, false],
    do: {:ok, value}

  defp placement(_value),
    do: Authoring.error("Topology Agent node must be an atom or topology reference")

  def plain_static_map(value) when is_map(value) and not is_struct(value) do
    with :ok <- static(value), do: {:ok, value}
  end

  def plain_static_map(_), do: Authoring.error("Expected a static plain map")

  defp static(value) do
    case Jido.Authoring.Config.validate_static_data(value) do
      :ok -> static_references(value)
      _ -> Authoring.error("Topology data must not contain runtime values")
    end
  end

  defp static_references(%Reference{} = reference), do: Reference.validate(reference)
  defp static_references(%Ref{} = reference), do: Ref.validate(reference)

  defp static_references(value) when is_map(value) and not is_struct(value) do
    Enum.reduce_while(value, :ok, fn {key, item}, :ok ->
      case static_references(key) do
        :ok ->
          case static_references(item) do
            :ok -> {:cont, :ok}
            {:error, _error} = error -> {:halt, error}
          end

        {:error, _error} = error ->
          {:halt, error}
      end
    end)
  end

  defp static_references(value) when is_list(value) do
    Enum.reduce_while(value, :ok, fn item, :ok ->
      case static_references(item) do
        :ok -> {:cont, :ok}
        {:error, _error} = error -> {:halt, error}
      end
    end)
  end

  defp static_references(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> static_references()

  defp static_references(_value), do: :ok

  @doc false
  def agent_source(entry), do: Map.get(entry, :definition) || Map.get(entry, :module)

  defp agent_selection(attrs) do
    case {Map.get(attrs, :module), Map.get(attrs, :definition)} do
      {nil, %Jido.Agent{} = value} ->
        with {:ok, definition} <- at(:definition, Jido.Agent.validate_definition(value)),
             do: {:ok, %{definition: definition}}

      {module, nil} when not is_nil(module) ->
        with :ok <-
               at(
                 :module,
                 if(is_atom(module), do: :ok, else: Authoring.error("Expected an Agent module"))
               ),
             {:ok, _} <- at(:module, agent_definition(module)),
             do: {:ok, %{module: module}}

      _ ->
        Authoring.error("An Agent entry requires exactly one module or neutral definition")
    end
  end

  @doc false
  def agent_definition(%Jido.Agent{} = definition), do: Jido.Agent.Source.definition(definition)

  def agent_definition(module) when is_atom(module) and not is_nil(module),
    do: Jido.Agent.Source.definition(module)

  def agent_definition(_module), do: Authoring.error("Expected an Agent module")

  defp path(value) when is_binary(value) and byte_size(value) > 0 do
    case Jido.Signal.Router.add(Jido.Signal.Router.new!(), {value, __MODULE__}) do
      {:ok, _} -> :ok
      _ -> Authoring.error("Invalid Bus subscription path")
    end
  end

  defp path(_), do: Authoring.error("Bus subscription path must be a nonempty string")

  defp positive(value, _field) when is_integer(value) and value > 0, do: :ok

  defp positive(_, field),
    do: at(field, Authoring.error("Expected a positive integer", %{field: field}))

  defp one_of(value, allowed, field) do
    if value in allowed,
      do: :ok,
      else:
        at(field, Authoring.error("Unsupported topology option", %{field: field, value: value}))
  end

  defp names(definition) do
    declarations =
      for field <- [:agents, :groups, :resources, :imports, :includes, :children],
          do: {field, Map.fetch!(definition, field)}

    with :ok <- unique_entries(declarations, "Duplicate topology key"),
         :ok <- unique_entries([exports: definition.exports], "Duplicate topology export"),
         do: :ok
  end

  defp unique_entries(collections, message) do
    entries =
      for {field, entries} <- collections,
          {entry, index} <- Enum.with_index(entries),
          do: {entry.key, [field, index, :key]}

    Enum.reduce_while(entries, MapSet.new(), fn {key, path}, seen ->
      if MapSet.member?(seen, key),
        do: {:halt, at(path, Authoring.error(message))},
        else: {:cont, MapSet.put(seen, key)}
    end)
    |> case do
      %MapSet{} -> :ok
      error -> error
    end
  end

  defp unique(values, message) do
    if length(values) == MapSet.size(MapSet.new(values)), do: :ok, else: Authoring.error(message)
  end

  defp at(field, result), do: Authoring.at(result, field)

  def layers(edges) do
    {remaining, dependents} =
      Enum.reduce(edges, {%{}, %{}}, fn {key, deps}, {remaining, dependents} ->
        deps = Enum.uniq(deps)

        dependents =
          Enum.reduce(deps, dependents, fn dependency, acc ->
            Map.update(acc, dependency, [key], &[key | &1])
          end)

        {Map.put(remaining, key, length(deps)), dependents}
      end)

    ready = for {key, 0} <- remaining, do: key
    collect_layers(remaining, dependents, Enum.sort(ready), [])
  end

  defp collect_layers(remaining, _dependents, [], acc) when map_size(remaining) == 0,
    do: {:ok, Enum.reverse(acc)}

  defp collect_layers(_remaining, _dependents, [], _acc),
    do: Authoring.error("Topology startup or ownership graph contains a cycle")

  defp collect_layers(remaining, dependents, ready, acc) do
    remaining = Map.drop(remaining, ready)

    {remaining, next} =
      Enum.reduce(ready, {remaining, MapSet.new()}, fn key, {counts, next} ->
        Enum.reduce(Map.get(dependents, key, []), {counts, next}, fn dependent, {counts, next} ->
          count = Map.fetch!(counts, dependent) - 1
          counts = Map.put(counts, dependent, count)
          next = if count == 0, do: MapSet.put(next, dependent), else: next
          {counts, next}
        end)
      end)

    collect_layers(remaining, dependents, next |> MapSet.to_list() |> Enum.sort(), [ready | acc])
  end
end
