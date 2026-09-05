defmodule Jido.Topology.Validation do
  @moduledoc false
  alias Jido.Agent.Authoring
  alias Jido.Topology.{Ref, Reference}

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
    do: Authoring.error("Topology inclusion depth exceeds 32")

  def definition(%Jido.Topology{} = attrs, ancestors, depth),
    do: definition(Map.from_struct(attrs), ancestors, depth)

  def definition(attrs, ancestors, depth) do
    with {:ok, attrs} <- Authoring.attrs(attrs),
         :ok <- Authoring.keys(attrs, @fields),
         {:ok, name} <- key(Map.get(attrs, :name)),
         schema = Map.get(attrs, :schema, Zoi.object(%{})),
         :ok <- field(:schema, schema),
         {:ok, metadata} <- plain_static_map(Map.get(attrs, :metadata, %{})),
         {:ok, agents} <- entries(attrs, :agents, :agent),
         {:ok, groups} <- entries(attrs, :groups, :group),
         {:ok, resources} <- entries(attrs, :resources, :bus),
         {:ok, relationships} <- entries(attrs, :relationships, :owns),
         {:ok, connections} <- entries(attrs, :connections, :subscribe),
         {:ok, startup} <- entry(:startup, Map.get(attrs, :startup, %{})),
         {:ok, imports} <- entries(attrs, :imports, :import),
         {:ok, exports} <- entries(attrs, :exports, :export),
         {:ok, includes} <-
           Authoring.traverse(Map.get(attrs, :includes, []), &include(&1, ancestors, depth)) do
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
        includes: includes
      }

      with :ok <- names(definition), do: {:ok, definition}
    end
  end

  defp entries(attrs, field, kind),
    do: Authoring.traverse(Map.get(attrs, field, []), &entry(kind, &1))

  def entry(kind, attrs) do
    with {:ok, attrs} <- Authoring.attrs(attrs),
         :ok <- Authoring.keys(attrs, fields(kind)),
         {:ok, value} <- normalize(kind, attrs),
         :ok <- static_entry(kind, value),
         do: {:ok, value}
  end

  defp static_entry(:include, _value), do: :ok
  defp static_entry(_kind, value), do: static(value)

  defp fields(:agent), do: [:key, :module, :initial_state, :depends_on]
  defp fields(:group), do: fields(:agent) ++ [:count, :members, :key_by]
  defp fields(:bus), do: [:key, :config]
  defp fields(:owns), do: [:parent, :child, :on_parent_exit]
  defp fields(:subscribe), do: [:agent, :to, :path]
  defp fields(:startup), do: [:concurrency, :ready, :max_agents, :retry_interval, :task_timeout]
  defp fields(:import), do: [:key, :kind]
  defp fields(:export), do: [:key, :kind, :from]
  defp fields(:include), do: [:key, :topology, :inputs, :bindings]
  defp fields(:binding), do: [:key, :to]

  defp normalize(kind, attrs) when kind in [:agent, :group] do
    with {:ok, name} <- key(attrs[:key]),
         :ok <- agent_module(attrs[:module]),
         {:ok, state} <- initial_state(Map.get(attrs, :initial_state, %{})),
         {:ok, deps} <- Authoring.traverse(Map.get(attrs, :depends_on, []), &Ref.target/1) do
      agent = %{key: name, module: attrs.module, initial_state: state, depends_on: deps}
      if kind == :agent, do: {:ok, agent}, else: group(agent, attrs)
    end
  end

  defp normalize(:bus, attrs) do
    with {:ok, name} <- key(attrs[:key]),
         {:ok, config} <- Authoring.options(Map.get(attrs, :config, [])),
         :ok <- reserved(config, [:name, :jido, :registry]) do
      {:ok, %{key: name, config: config}}
    end
  end

  defp normalize(:owns, attrs) do
    with {:ok, parent} <- Ref.target(attrs[:parent]),
         {:ok, child} <- Ref.target(attrs[:child]),
         policy = Map.get(attrs, :on_parent_exit, :stop),
         :ok <- one_of(policy, [:stop, :continue, :emit_orphan], :on_parent_exit) do
      {:ok, %{parent: parent, child: child, on_parent_exit: policy}}
    end
  end

  defp normalize(:subscribe, attrs) do
    with {:ok, agent} <- Ref.target(attrs[:agent]),
         {:ok, bus} <- Ref.target(attrs[:to]),
         :ok <- path(attrs[:path]) do
      {:ok, %{agent: agent, to: bus, path: attrs.path}}
    end
  end

  defp normalize(:startup, attrs) do
    result =
      Map.merge(
        %{
          concurrency: 32,
          ready: :all,
          max_agents: 10_000,
          retry_interval: 1_000,
          task_timeout: 10_000
        },
        attrs
      )

    with :ok <- positive(result.concurrency, :concurrency),
         :ok <- positive(result.max_agents, :max_agents),
         :ok <- positive(result.retry_interval, :retry_interval),
         :ok <- positive(result.task_timeout, :task_timeout),
         :ok <- one_of(result.ready, [:all], :ready),
         do: {:ok, result}
  end

  defp normalize(:import, attrs) do
    with {:ok, key} <- key(attrs[:key]),
         :ok <- one_of(attrs[:kind], [:bus], :kind),
         do: {:ok, %{key: key, kind: :bus}}
  end

  defp normalize(:export, attrs) do
    with {:ok, key} <- key(attrs[:key]),
         :ok <- one_of(attrs[:kind], [:agent, :group, :bus], :kind),
         {:ok, from} <- Ref.target(attrs[:from]),
         do: {:ok, %{key: key, kind: attrs.kind, from: from}}
  end

  defp normalize(:binding, attrs) do
    with {:ok, key} <- key(attrs[:key]),
         {:ok, to} <- Ref.target(attrs[:to]),
         do: {:ok, %{key: key, to: to}}
  end

  defp normalize(:include, attrs), do: include(attrs, [], 0)

  defp include(attrs, ancestors, depth) do
    with {:ok, attrs} <- Authoring.attrs(attrs),
         :ok <- Authoring.keys(attrs, fields(:include)),
         {:ok, key} <- key(attrs[:key]),
         {:ok, source, ancestors} <- included_source(attrs[:topology], ancestors),
         {:ok, definition} <- definition(source, ancestors, depth + 1),
         {:ok, inputs} <- plain_static_map(Map.get(attrs, :inputs, %{})),
         {:ok, bindings} <- bindings(Map.get(attrs, :bindings, [])),
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
  end

  defp included_source(%Jido.Topology{} = value, ancestors), do: {:ok, value, ancestors}

  defp included_source(value, ancestors) when is_map(value) or is_list(value),
    do: {:ok, value, ancestors}

  defp included_source(_, _), do: Authoring.error("Expected a topology module or definition")

  defp bindings(value) when is_map(value) and not is_struct(value) do
    value |> Enum.sort() |> Enum.map(fn {key, to} -> %{key: key, to: to} end) |> bindings()
  end

  defp bindings(values), do: Authoring.traverse(values, &entry(:binding, &1))

  defp group(agent, %{members: members, key_by: key_by} = attrs) do
    cond do
      Map.has_key?(attrs, :count) ->
        Authoring.error("A group uses count or members, not both")

      not (is_atom(key_by) or is_binary(key_by)) ->
        Authoring.error("Group key_by must name a member field")

      not (is_list(members) or match?(%Reference{kind: :input}, members)) ->
        Authoring.error("Group members must be a list or input reference")

      true ->
        {:ok, Map.merge(agent, %{members: members, key_by: key_by})}
    end
  end

  defp group(agent, attrs) do
    count = Map.get(attrs, :count, 1)

    cond do
      Map.has_key?(attrs, :members) or Map.has_key?(attrs, :key_by) ->
        Authoring.error("A keyed group requires members and key_by")

      is_integer(count) and count >= 0 ->
        {:ok, Map.put(agent, :count, count)}

      match?(%Reference{kind: :input}, count) ->
        {:ok, Map.put(agent, :count, count)}

      true ->
        Authoring.error("Group count must be nonnegative or an input reference")
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

  defp plain_static_map(value) when is_map(value) and not is_struct(value) do
    with :ok <- static(value), do: {:ok, value}
  end

  defp plain_static_map(_), do: Authoring.error("Expected a static plain map")

  defp static(value) do
    case Jido.Action.validate_static_data(value) do
      :ok -> :ok
      _ -> Authoring.error("Topology data must not contain runtime values")
    end
  end

  defp agent_module(module) when is_atom(module) and not is_nil(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :agent, 0),
      do: :ok,
      else: Authoring.error("Expected an Agent module", %{module: module})
  end

  defp agent_module(_), do: Authoring.error("Expected an Agent module")

  defp reserved(config, keys) do
    if Enum.any?(keys, &Keyword.has_key?(config, &1)),
      do: Authoring.error("Topology owns Bus name, Registry, and Jido scope"),
      else: :ok
  end

  defp path(value) when is_binary(value) and byte_size(value) > 0 do
    case Jido.Signal.Router.add(Jido.Signal.Router.new!(), {value, __MODULE__}) do
      {:ok, _} -> :ok
      _ -> Authoring.error("Invalid Bus subscription path")
    end
  end

  defp path(_), do: Authoring.error("Bus subscription path must be a nonempty string")

  defp positive(value, _field) when is_integer(value) and value > 0, do: :ok
  defp positive(_, field), do: Authoring.error("Expected a positive integer", %{field: field})

  defp one_of(value, allowed, field) do
    if value in allowed,
      do: :ok,
      else: Authoring.error("Unsupported topology option", %{field: field, value: value})
  end

  defp names(definition) do
    declarations =
      definition.agents ++
        definition.groups ++ definition.resources ++ definition.imports ++ definition.includes

    with :ok <- unique(Enum.map(declarations, & &1.key), "Duplicate topology key"),
         :ok <- unique(Enum.map(definition.exports, & &1.key), "Duplicate topology export"),
         do: :ok
  end

  defp unique(values, message) do
    if length(values) == MapSet.size(MapSet.new(values)), do: :ok, else: Authoring.error(message)
  end

  def layers(edges), do: layers(edges, [])
  defp layers(edges, acc) when map_size(edges) == 0, do: {:ok, Enum.reverse(acc)}

  defp layers(edges, acc) do
    ready =
      edges
      |> Enum.filter(fn {_, deps} -> deps == [] end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    if ready == [] do
      Authoring.error("Topology startup or ownership graph contains a cycle")
    else
      completed = MapSet.new(ready)

      remaining =
        Map.new(Map.drop(edges, ready), fn {key, deps} ->
          {key, Enum.reject(deps, &MapSet.member?(completed, &1))}
        end)

      layers(remaining, [ready | acc])
    end
  end
end
