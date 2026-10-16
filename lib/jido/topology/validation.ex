defmodule Jido.Topology.Validation do
  @moduledoc false
  alias Jido.Agent.Authoring
  alias Jido.Topology.{EntryMetadata, Ref, Reference, Resource}

  @fields [:name, :schema, :metadata, :startup] ++
            Enum.map(EntryMetadata.collections(), &elem(&1, 1))

  def definition(attrs, ancestors \\ [], depth \\ 0) do
    with {:ok, definition, _resolved} <- resolve(attrs, %{}, ancestors, depth),
         do: {:ok, definition}
  end

  def resolve(attrs, resolved, ancestors \\ [], depth \\ 0)

  def resolve(_, _, _, depth) when depth > 32,
    do: Authoring.error("Topology depth exceeds 32")

  def resolve(%Jido.Topology{} = attrs, resolved, ancestors, depth),
    do: resolve(Map.from_struct(attrs), resolved, ancestors, depth)

  def resolve(attrs, resolved, ancestors, depth) do
    with {:ok, attrs} <- Authoring.attrs(attrs),
         :ok <- Authoring.keys(attrs, @fields),
         {:ok, name} <- at(:name, key(Map.get(attrs, :name))),
         schema = Map.get(attrs, :schema, Zoi.object(%{})),
         :ok <- at(:schema, validate_schema(schema)),
         {:ok, metadata} <- at(:metadata, plain_static_map(Map.get(attrs, :metadata, %{}))),
         {:ok, agents, resolved} <- entries(attrs, :agents, :agent, resolved),
         {:ok, groups, resolved} <- entries(attrs, :groups, :group, resolved),
         {:ok, resources, resolved} <- entries(attrs, :resources, :resource, resolved),
         {:ok, relationships, resolved} <- entries(attrs, :relationships, :owns, resolved),
         {:ok, connections, resolved} <- entries(attrs, :connections, :subscribe, resolved),
         {:ok, startup} <- at(:startup, entry(:startup, Map.get(attrs, :startup, %{}))),
         {:ok, imports, resolved} <- entries(attrs, :imports, :import, resolved),
         {:ok, exports, resolved} <- entries(attrs, :exports, :export, resolved),
         {:ok, children} <-
           Authoring.traverse_indexed(
             Map.get(attrs, :children, []),
             &Jido.Topology.Child.normalize(&1, ancestors, depth)
           )
           |> Authoring.at(:children),
         {:ok, includes, resolved} <-
           traverse_resolved(
             Map.get(attrs, :includes, []),
             resolved,
             &include(&1, ancestors, depth, &2)
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

      with :ok <- names(definition), do: {:ok, definition, resolved}
    end
  end

  defp validate_schema(%Zoi.Types.Map{} = schema), do: Jido.Agent.State.validate_schema(schema)
  defp validate_schema(_), do: Authoring.error("Topology input schema must be a Zoi object")

  defp entries(attrs, field, kind, resolved),
    do:
      traverse_resolved(Map.get(attrs, field, []), resolved, &entry(kind, &1, &2))
      |> Authoring.at(field)

  defp traverse_resolved(entries, resolved, fun),
    do: traverse_resolved(entries, resolved, fun, 0, [])

  defp traverse_resolved([], resolved, _fun, _index, acc),
    do: {:ok, Enum.reverse(acc), resolved}

  defp traverse_resolved([entry | rest], resolved, fun, index, acc) do
    case Authoring.at(fun.(entry, resolved), index) do
      {:ok, entry, resolved} -> traverse_resolved(rest, resolved, fun, index + 1, [entry | acc])
      error -> error
    end
  end

  defp traverse_resolved(_, _resolved, _fun, _index, _acc),
    do: Authoring.error("Expected a proper list")

  def entry(kind, attrs) do
    with {:ok, value, _resolved} <- entry(kind, attrs, %{}), do: {:ok, value}
  end

  defp entry(kind, attrs, resolved) do
    with {:ok, attrs} <- Authoring.attrs(attrs),
         :ok <- entry_keys(attrs, kind),
         attrs = EntryMetadata.apply_defaults(kind, attrs),
         {:ok, value, resolved} <- normalize(kind, attrs, resolved),
         :ok <- static_entry(kind, value),
         do: {:ok, value, resolved}
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

  defp normalize(kind, attrs, resolved) when kind in [:agent, :group] do
    with {:ok, name} <- at(:key, key(attrs[:key])),
         {:ok, selection, resolved} <- agent_selection(attrs, resolved),
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

      with {:ok, value} <- if(kind == :agent, do: {:ok, agent}, else: group(agent, attrs)),
           do: {:ok, value, resolved}
    end
  end

  defp normalize(:include, attrs, resolved), do: include(attrs, [], 0, resolved)

  defp normalize(kind, attrs, resolved) do
    with {:ok, value} <- normalize(kind, attrs), do: {:ok, value, resolved}
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

  defp resource_config(kind, config) do
    case Resource.validate(kind, config) do
      {:error, %{details: %{field: field}}} = error -> at(field, error)
      result -> at(:config, result)
    end
  end

  defp include(attrs, ancestors, depth, resolved) do
    with {:ok, attrs} <- Authoring.attrs(attrs),
         :ok <- entry_keys(attrs, :include),
         attrs = EntryMetadata.apply_defaults(:include, attrs),
         {:ok, key} <- at(:key, key(attrs[:key])),
         {:ok, source, _owner, ancestors} <-
           at(:topology, Jido.Topology.Source.load(attrs[:topology], ancestors, :include)),
         {:ok, definition, resolved} <-
           at(:topology, resolve(source, resolved, ancestors, depth + 1)),
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
       }, resolved}
    end
  end

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

  defp agent_selection(attrs, resolved) do
    case {Map.get(attrs, :module), Map.get(attrs, :definition)} do
      {nil, %Jido.Agent{} = value} ->
        with {:ok, {:ok, definition, _specs, _schema}, resolved} <-
               at(:definition, Jido.Agent.Source.resolve(value, resolved)),
             do: {:ok, %{definition: definition}, resolved}

      {module, nil} when is_atom(module) and not is_nil(module) ->
        with {:ok, _validation, resolved} <-
               at(:module, Jido.Agent.Source.resolve(module, resolved)),
             do: {:ok, %{module: module}, resolved}

      {module, nil} when not is_nil(module) ->
        at(:module, Authoring.error("Expected an Agent module"))

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

  @doc false
  def names(definition) do
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
