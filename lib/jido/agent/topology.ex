defmodule Jido.Agent.Topology do
  @moduledoc """
  Static topology authoring data on a `Jido.Agent`.

  This module checks declaration shape and keeps the existing collections.
  It returns a plain map. It does not resolve sources, expand
  groups or includes, bind input, or start processes. Those operations belong
  to a later composition boundary.

  The enclosing Agent supplies the definition, state, and lifecycle. Topology
  is composition intent on that Agent. A plain Agent has `topology: nil`.
  No topology input schema is added by default. An explicit `schema` remains
  available for mapped composition data.

  Worker `activation: :eager | :lazy | :deferred` records process startup policy within
  the Agent Activation. It does not set when a child Agent value is constructed.
  Fixed values and `state/1` references describe the initial child set. State
  references are snapshot intent, not a live resize rule. Later composition
  changes must be explicit.

  Agent, group, and child entries share one source contract. A child Agent
  supplies its own root behavior. Static includes take explicit composition
  maps. `root()` names the enclosing Agent. Containment (`placement`) stays
  separate from logical ownership edges. Group connections state `delivery`
  as `:one` or `:broadcast`. Imported Agent Refs grant no lifecycle authority.
  Graph binding, dependency cycles, endpoint resolution, and process handling
  remain outside this declaration-shape boundary.
  """

  alias Jido.Agent.Authoring
  alias Jido.Agent.State
  alias Jido.Agent.Topology.{Ref, Reference}
  alias Jido.Authoring.Config

  @agent_fields [
    key: [type: :any, required: true],
    module: [type: :atom],
    definition: [type: :any],
    initial_state: [type: :any, default: %{}],
    activation: [type: {:in, [:eager, :lazy, :deferred]}, default: :eager],
    placement: [type: {:in, [:owned, :independent]}, default: :owned],
    depends_on: [type: {:list, :any}, default: []],
    node: [type: :any]
  ]
  @entries [
    agent: {:agents, @agent_fields},
    group:
      {:groups,
       @agent_fields ++
         [count: [type: :any], members: [type: :any], key_by: [type: :any]]},
    resource:
      {:resources,
       [
         key: [type: :any, required: true],
         kind: [type: {:in, [:bus]}, default: :bus],
         config: [type: :any, default: []]
       ]},
    owns:
      {:relationships,
       [
         parent: [type: :any, required: true],
         child: [type: :any, required: true],
         on_parent_exit: [type: {:in, [:stop, :continue, :emit_orphan]}, default: :stop]
       ]},
    subscribe:
      {:connections,
       [
         agent: [type: :any, required: true],
         to: [type: :any, required: true],
         path: [type: :string, required: true],
         delivery: [type: {:in, [:broadcast, :one]}]
       ]},
    include:
      {:includes,
       [
         key: [type: :any, required: true],
         topology: [type: :any, required: true],
         inputs: [type: :map, default: %{}],
         bindings: [type: :any, default: []]
       ]},
    runtime_child:
      {:children,
       Keyword.put(@agent_fields, :activation,
         type: {:in, [:eager, :lazy, :deferred]},
         default: :lazy
       ) ++
         [
           gate: [type: :any, default: %{}],
           max_restarts: [type: :non_neg_integer, default: 3],
           max_seconds: [type: :pos_integer, default: 5]
         ]},
    import:
      {:imports,
       [
         key: [type: :any, required: true],
         kind: [type: {:in, [:agent, :bus]}, default: :bus],
         ref: [type: :any]
       ]},
    export:
      {:exports,
       [
         key: [type: :any, required: true],
         kind: [type: {:in, [:agent, :group, :bus]}, required: true],
         from: [type: :any, required: true]
       ]},
    startup:
      {nil,
       [
         concurrency: [type: :pos_integer, default: 32],
         max_agents: [type: :pos_integer, default: 10_000],
         retry_interval: [type: :pos_integer, default: 1_000],
         task_timeout: [type: :pos_integer, default: 10_000]
       ]},
    binding: {nil, [key: [type: :any, required: true], to: [type: :any, required: true]]}
  ]

  @doc false
  def schema(kind), do: @entries |> Keyword.fetch!(kind) |> elem(1)

  @doc false
  def collections do
    for {kind, {collection, _schema}} <- @entries, not is_nil(collection), do: {kind, collection}
  end

  @doc false
  def validate(nil), do: {:ok, nil}

  def validate(value) when is_map(value) and not is_struct(value) do
    fields = [:name, :schema, :metadata, :startup] ++ Enum.map(collections(), &elem(&1, 1))

    with :ok <- Authoring.keys(value, fields),
         :ok <- static(Map.get(value, :name)) |> Authoring.at(:name),
         :ok <- optional_schema(value) |> Authoring.at(:schema),
         {:ok, metadata} <-
           plain_static_map(Map.get(value, :metadata, %{})) |> Authoring.at(:metadata),
         {:ok, startup} <-
           entry(:startup, Map.get(value, :startup, %{})) |> Authoring.at(:startup),
         {:ok, entries} <- Authoring.traverse(collections(), &collection(value, &1)),
         topology =
           value
           |> Map.merge(Map.new(entries))
           |> Map.put(:metadata, metadata)
           |> Map.put(:startup, startup),
         :ok <- unique_keys(topology),
         :ok <- connections(topology) do
      {:ok, topology}
    end
  end

  def validate(_value), do: Authoring.error("Agent topology must be a plain map or nil")

  defp optional_schema(%{schema: %Zoi.Types.Map{} = schema}), do: State.validate_schema(schema)

  defp optional_schema(%{schema: _}),
    do: Authoring.error("Topology input schema must be a Zoi object")

  defp optional_schema(_value), do: :ok

  defp collection(value, {kind, field}) do
    with {:ok, items} <-
           Authoring.traverse_indexed(Map.get(value, field, []), &entry(kind, &1))
           |> Authoring.at(field),
         do: {:ok, {field, items}}
  end

  defp entry(kind, value) do
    with {:ok, attrs} <- Authoring.attrs(value),
         {:ok, fields} <- Authoring.validate_options(attrs, schema(kind)),
         {:ok, fields} <- normalize_entry(kind, fields),
         {:ok, fields} <- normalize_source(kind, fields),
         :ok <- entry_shape(kind, fields),
         :ok <- static_fields(kind, fields) do
      {:ok, fields}
    end
  end

  defp normalize_entry(:group, fields) when not is_map_key(fields, :members),
    do: {:ok, Map.put_new(fields, :count, 1)}

  defp normalize_entry(:include, %{topology: topology} = fields)
       when is_map(topology) and not is_struct(topology) do
    with {:ok, topology} <- validate(fields.topology) |> Authoring.at(:topology),
         {:ok, bindings} <-
           Authoring.traverse_indexed(fields.bindings, &entry(:binding, &1))
           |> Authoring.at(:bindings) do
      {:ok, %{fields | topology: topology, bindings: bindings}}
    end
  end

  defp normalize_entry(:include, _fields),
    do: Authoring.error("Expected a static plain map") |> Authoring.at(:topology)

  defp normalize_entry(_kind, fields), do: {:ok, fields}

  defp normalize_source(kind, %{definition: definition} = fields)
       when kind in [:agent, :group, :runtime_child] do
    with {:ok, definition} <-
           Jido.Agent.validate_definition(definition) |> Authoring.at(:definition),
         do: {:ok, %{fields | definition: definition}}
  end

  defp normalize_source(_kind, fields), do: {:ok, fields}

  defp entry_shape(kind, fields) when kind in [:agent, :group, :runtime_child] do
    with :ok <- key(fields.key),
         :ok <- child_source(fields),
         {:ok, _} <- plain_static_map(fields.initial_state) |> Authoring.at(:initial_state),
         :ok <- group_shape(kind, fields),
         :ok <- gate_shape(kind, fields) do
      Authoring.check_each(fields.depends_on, &endpoint/1) |> Authoring.at(:depends_on)
    end
  end

  defp entry_shape(:include, fields), do: key(fields.key)

  defp entry_shape(:owns, fields) do
    with :ok <- endpoint(fields.parent) |> Authoring.at(:parent),
         :ok <- endpoint(fields.child) |> Authoring.at(:child) do
      if endpoint_identity(fields.parent) == endpoint_identity(fields.child),
        do: Authoring.error("An Agent cannot own itself"),
        else: :ok
    end
  end

  defp entry_shape(:subscribe, fields) do
    with :ok <- endpoint(fields.agent) |> Authoring.at(:agent),
         :ok <- endpoint(fields.to) |> Authoring.at(:to) do
      if fields.path == "", do: Authoring.error("Signal path must not be empty"), else: :ok
    end
  end

  defp entry_shape(:binding, fields) do
    with :ok <- key(fields.key), do: endpoint(fields.to) |> Authoring.at(:to)
  end

  defp entry_shape(:export, fields) do
    with :ok <- key(fields.key), do: endpoint(fields.from) |> Authoring.at(:from)
  end

  defp entry_shape(:import, fields) do
    with :ok <- key(fields.key), do: imported_ref(fields)
  end

  defp entry_shape(:resource, fields), do: key(fields.key)

  defp entry_shape(:startup, _fields), do: :ok

  defp imported_ref(%{kind: :agent, ref: ref}) do
    case Jido.Agent.Ref.validate(ref) do
      {:ok, _} -> :ok
      error -> Authoring.at(error, :ref)
    end
  end

  defp imported_ref(%{ref: _}), do: Authoring.error("Only an Agent import accepts an Agent Ref")
  defp imported_ref(_fields), do: :ok

  defp child_source(fields) do
    case {Map.fetch(fields, :module), Map.fetch(fields, :definition)} do
      {{:ok, module}, :error} when is_atom(module) and module not in [nil, true, false] -> :ok
      {:error, {:ok, %Jido.Agent{id: nil, state: nil}}} -> :ok
      _ -> Authoring.error("A child requires exactly one module or neutral Agent definition")
    end
  end

  defp group_shape(:group, %{count: _, members: _}),
    do: Authoring.error("A group accepts count or members, not both")

  defp group_shape(:group, %{count: count} = fields) do
    cond do
      Map.has_key?(fields, :key_by) ->
        Authoring.error("key_by requires group members")

      is_integer(count) and count >= 0 ->
        :ok

      source_reference?(count) ->
        :ok

      true ->
        Authoring.error("Group count must be a non-negative integer or state/input reference")
    end
  end

  defp group_shape(:group, %{members: members} = fields) do
    with :ok <- key(Map.get(fields, :key_by)) |> Authoring.at(:key_by) do
      cond do
        source_reference?(members) -> :ok
        is_list(members) -> member_keys(members, fields.key_by)
        true -> Authoring.error("Group members must be a list or state/input reference")
      end
    end
  end

  defp group_shape(_kind, _fields), do: :ok

  defp gate_shape(:runtime_child, %{gate: gate}) do
    with {:ok, gate} <- plain_static_map(gate),
         :ok <- Authoring.keys(gate, [:commands, :events, :to]),
         {:ok, _} <-
           Authoring.traverse_indexed(Map.get(gate, :commands, []), &gate_command/1),
         {:ok, events} <-
           Authoring.traverse_indexed(Map.get(gate, :events, []), fn
             path when is_binary(path) and byte_size(path) > 0 -> {:ok, path}
             _ -> Authoring.error("Gate events require Signal paths")
           end) do
      if events != [] or Map.has_key?(gate, :to), do: endpoint(gate[:to]), else: :ok
    end
    |> Authoring.at(:gate)
  end

  defp gate_shape(_kind, _fields), do: :ok

  defp gate_command(value) do
    with {:ok, command} <- Authoring.attrs(value),
         :ok <- Authoring.keys(command, [:type, :member]),
         true <-
           is_binary(command[:type]) and command.type != "" and
             not String.contains?(command.type, "*"),
         :ok <- endpoint(command[:member]) do
      {:ok, command}
    else
      false -> Authoring.error("A gate command requires an exact Signal type")
      error -> error
    end
  end

  defp source_reference?(%Reference{kind: kind, key: key}) when kind in [:state, :input],
    do: Reference.key?(key)

  defp source_reference?(_value), do: false

  defp member_keys(members, field) do
    with {:ok, keys} <-
           Authoring.traverse_indexed(members, &member_key(&1, field)),
         do: Authoring.unique_keys(keys)
  end

  defp member_key(member, field) when is_map(member) and not is_struct(member) do
    with :ok <- key(Map.get(member, field)), do: {:ok, Map.fetch!(member, field)}
  end

  defp member_key(_member, _field),
    do: Authoring.error("Group members must be plain maps with stable keys")

  defp key(value) do
    if Authoring.key?(value),
      do: :ok,
      else: Authoring.error("Expected a nonempty atom or string key")
  end

  defp endpoint(%Reference{kind: :root, key: nil}), do: :ok

  defp endpoint({:group, group, member}) do
    with :ok <- key(group), do: key(member)
  end

  defp endpoint({:child, child}), do: key(child)

  defp endpoint(%Ref{component: component, key: value}) do
    with :ok <- key(component), do: key(value)
  end

  defp endpoint(value), do: key(value)

  defp endpoint_identity(%Ref{component: component, key: key}),
    do: {:export, Authoring.key_identity(component), Authoring.key_identity(key)}

  defp endpoint_identity({:group, group, member}),
    do: {:group, Authoring.key_identity(group), Authoring.key_identity(member)}

  defp endpoint_identity({:child, child}), do: Authoring.key_identity(child)
  defp endpoint_identity(%Reference{} = ref), do: ref
  defp endpoint_identity(key), do: Authoring.key_identity(key)

  defp unique_keys(topology) do
    with :ok <-
           Authoring.unique_keys(
             Enum.flat_map(
               [:agents, :groups, :resources, :includes, :children, :imports],
               fn field -> Enum.map(topology[field], & &1.key) end
             )
           ),
         do: Authoring.unique_keys(Enum.map(topology.exports, & &1.key)) |> Authoring.at(:exports)
  end

  defp connections(topology) do
    kinds = Map.new(topology.groups, &{endpoint_identity(&1.key), :group})

    kinds =
      for include <- topology.includes, export <- include.topology.exports, into: kinds do
        {endpoint_identity(%Ref{component: include.key, key: export.key}), export.kind}
      end

    topology.connections
    |> Authoring.traverse_indexed(fn connection ->
      fallback = if is_struct(connection.agent, Ref), do: :unknown, else: :agent
      kind = Map.get(kinds, endpoint_identity(connection.agent), fallback)

      connection_delivery(kind, connection)
    end)
    |> case do
      {:ok, _} -> :ok
      error -> Authoring.at(error, :connections)
    end
  end

  defp connection_delivery(:group, connection) when not is_map_key(connection, :delivery),
    do: Authoring.error("Group delivery requires :broadcast or :one")

  defp connection_delivery(kind, connection)
       when kind not in [:group, :unknown] and is_map_key(connection, :delivery),
       do: Authoring.error("Delivery mode requires a declared group target")

  defp connection_delivery(_kind, connection), do: {:ok, connection}

  defp static_fields(kind, fields) do
    checked =
      case kind do
        :include -> [:topology, :bindings]
        kind when kind in [:agent, :group, :runtime_child] -> [:definition, :initial_state, :gate]
        _ -> []
      end

    fields
    |> Map.drop(checked)
    |> Enum.to_list()
    |> Authoring.check_each(fn {key, value} ->
      static(value) |> Authoring.at(key)
    end)
  end

  @doc false
  def plain_static_map(value) when is_map(value) and not is_struct(value) do
    with :ok <- static(value), do: {:ok, value}
  end

  def plain_static_map(_value), do: Authoring.error("Expected a static plain map")

  defp static(value) do
    case Config.validate_static_data(value) do
      :ok -> :ok
      {:error, reason} -> Authoring.error("Topology data must be static", %{reason: reason})
    end
  end
end
