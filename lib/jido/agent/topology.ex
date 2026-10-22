defmodule Jido.Agent.Topology do
  @moduledoc "Logical members and output connections. These declarations do not start processes."
  alias Jido.Agent.{Data, Error, Extension, Route, Validation}

  @doc "Creates a symbolic reference to one parent Agent state field."
  def state(key), do: %{kind: :state, key: key}

  @doc false
  def empty?(%{agents: [], connections: []}), do: true
  def empty?(_), do: false

  # These checks have no enclosing Agent. Full reference and contract checks
  # run when the complete candidate Agent is validated.
  @doc false
  def validate(value) do
    with {:ok, value} <-
           Data.fields(value, [:agents, :connections], %{agents: [], connections: []}),
         {:ok, agents} <- Error.at(Data.list(value.agents, &entry(:agent, &1)), :agents),
         {:ok, connections} <-
           Error.at(Data.list(value.connections, &entry(:connect, &1)), :connections),
         do: {:ok, %{agents: agents, connections: connections}}
  end

  @doc false
  def entry(:agent, value) do
    with {:ok, value} <-
           Data.fields(value, [:name, :definition, :count, :initial_state, :identities], %{
             count: 1,
             initial_state: %{}
           }),
         :ok <- Error.at(Data.name(value[:name]), :name),
         :ok <- identities(Map.get(value, :identities, %{})),
         true <- Map.has_key?(value, :definition) do
      {:ok, value}
    else
      false -> Error.fail(:invalid_member, :definition, "Expected an Agent definition or module")
      error -> error
    end
  end

  def entry(:connect, value) do
    with {:ok, value} <- Data.fields(value, [:path, :from, :to, :delivery], %{delivery: :single}),
         :ok <- Error.at(Data.path(value[:path]), :path),
         :ok <- Error.at(Data.plain_map(value[:from]), :from),
         :ok <- Error.at(Data.plain_map(value[:to]), :to),
         do: {:ok, value}
  end

  defp identities(value) when is_map(value) and not is_struct(value) do
    if Enum.all?(value, fn {slot, id} ->
         is_integer(slot) and slot > 0 and is_binary(id) and byte_size(id) > 0
       end),
       do: :ok,
       else: Error.fail(:invalid_member_identity, :identities, "Expected positive slots and IDs")
  end

  defp identities(_),
    do: Error.fail(:invalid_member_identity, :identities, "Expected a member identity Map")

  @doc false
  def normalize(value, parent, opts) do
    with {:ok, topology} <-
           Data.fields(value, [:agents, :connections], %{agents: [], connections: []}),
         {:ok, agents} <- Error.at(Data.list(topology.agents, &member(&1, parent, opts)), :agents),
         :ok <- Error.at(Data.unique(agents, & &1.name), :agents),
         {:ok, connections} <-
           Error.at(
             Data.list(topology.connections, &connection(&1, agents, parent.extensions)),
             :connections
           ),
         :ok <- Error.at(Data.unique(connections, &{&1.from, &1.to, &1.path}), :connections),
         topology = %{agents: agents, connections: connections},
         :ok <- compatibility(%{parent | topology: topology}, opts) do
      {:ok, topology}
    end
  end

  defp member(value, parent, opts) do
    with {:ok, member} <- entry(:agent, value),
         :ok <- reserved(member.name),
         :ok <- Error.at(count(member.count, parent.schema), :count),
         :ok <- Error.at(Data.plain_map(member.initial_state), :initial_state),
         :ok <- Error.at(references(member.initial_state, parent.schema), :initial_state),
         {:ok, definition} <- nested(member[:definition], opts),
         member = Map.put(member, :definition, definition),
         :ok <- initial(member, opts) do
      {:ok, member}
    end
  end

  defp reserved(:root),
    do: Error.fail(:reserved_name, :name, "The :root name belongs to the enclosing agent")

  defp reserved(_), do: :ok
  defp count(%{kind: :state} = ref, schema), do: reference(ref, schema)
  defp count(value, _), do: Data.positive(value)

  defp reference(value, schema) do
    with {:ok, ref} <- Data.fields(value, [:kind, :key]), :ok <- Data.name(ref[:key]) do
      if Keyword.has_key?(schema.fields, ref.key),
        do: :ok,
        else:
          Error.fail(:unknown_state_field, [], "Parent state field does not exist", %{
            key: ref.key
          })
    end
  end

  defp references(%{kind: :state} = value, schema), do: reference(value, schema)

  defp references(value, schema) when is_map(value) and not is_struct(value) do
    with {:ok, _} <-
           Data.list(Map.to_list(value), fn {key, v} ->
             with :ok <- Error.at(references(v, schema), key), do: {:ok, v}
           end),
         do: :ok
  end

  defp references(value, schema) when is_list(value) do
    with {:ok, _} <- Data.list(value, fn v -> with :ok <- references(v, schema), do: {:ok, v} end),
         do: :ok
  end

  defp references(value, _), do: Data.static(value)

  defp nested(value, opts) when is_map(value) do
    Validation.define(value, opts)
  end

  defp nested(value, opts) when is_atom(value) and value not in [nil, true, false] do
    if Keyword.get(opts, :related?, true) do
      case related(value, opts) do
        {:ok, _} -> {:ok, value}
        error -> error
      end
    else
      {:ok, value}
    end
  end

  defp nested(_, _),
    do: Error.fail(:invalid_member, :definition, "Expected an Agent definition or module")

  defp related(%Jido.Agent{id: nil, state: nil} = value, _opts), do: {:ok, value}

  defp related(module, opts) do
    seen = Keyword.get(opts, :seen, [])

    cond do
      module in seen ->
        Error.fail(:recursive_membership, :definition, "Member containment cannot be cyclic", %{
          module: module
        })

      Code.ensure_loaded?(module) and function_exported?(module, :definition, 0) ->
        Validation.define(module.definition(), Keyword.put(opts, :seen, [module | seen]))

      true ->
        Error.fail(:unresolved_definition, :definition, "Member definition is not available", %{
          module: module
        })
    end
  end

  defp initial(member, opts) do
    if Keyword.get(opts, :related?, true) do
      with {:ok, child} <- related(member.definition, opts),
           {:ok, schema} <- Jido.Agent.Validation.state_schema(child),
           :ok <- partial_initial(schema, member.initial_state),
           do: :ok
    else
      :ok
    end
  end

  defp contains_ref?(%{kind: :state}), do: true

  defp contains_ref?(value) when is_map(value) and not is_struct(value),
    do: Enum.any?(value, fn {_, v} -> contains_ref?(v) end)

  defp contains_ref?(value) when is_list(value), do: Enum.any?(value, &contains_ref?/1)
  defp contains_ref?(_), do: false

  defp partial_initial(schema, state) do
    partial_value(schema, state) |> Error.at(:initial_state)
  end

  # A symbolic value has no current value during authoring. Validate the known
  # parts and check the complete value again when an instance binds the input.
  defp partial_value(_schema, %{kind: :state}), do: :ok

  defp partial_value(%Zoi.Types.Map{fields: fields} = schema, state)
       when is_list(fields) and is_map(state) and not is_struct(state) do
    with {:ok, fields} <-
           Data.list(fields, fn {key, type} ->
             case Map.fetch(state, key) do
               {:ok, value} ->
                 if contains_ref?(value) do
                   with :ok <- Error.at(partial_value(type, value), key),
                        do: {:ok, {key, Zoi.any()}}
                 else
                   {:ok, {key, type}}
                 end

               :error ->
                 {:ok, {key, type}}
             end
           end) do
      case Data.initialize(%{schema | fields: fields}, state) do
        {:ok, _} -> :ok
        error -> error
      end
    end
  end

  defp partial_value(%Zoi.Types.Array{inner: inner} = schema, value) when is_list(value) do
    with {:ok, _} <- Data.parse_value(%{schema | inner: Zoi.any()}, value),
         {:ok, _} <-
           Data.list(value, fn item -> with :ok <- partial_value(inner, item), do: {:ok, item} end),
         do: :ok
  end

  defp partial_value(schema, value) do
    with {:ok, _} <- Data.parse_value(schema, value), do: :ok
  end

  defp connection(value, agents, extensions) do
    with {:ok, connection} <- entry(:connect, value),
         {:ok, from} <- Error.at(endpoint(connection[:from], agents, extensions), :from),
         {:ok, to} <- Error.at(endpoint(connection[:to], agents, extensions), :to),
         connection = %{connection | from: from, to: to},
         :ok <- delivery(connection, agents),
         :ok <- Extension.verify_connection(extensions, connection),
         do: {:ok, connection}
  end

  defp endpoint(%{kind: :agent} = value, agents, _extensions) do
    with {:ok, value} <- Data.fields(value, [:kind, :name]), :ok <- Data.name(value[:name]) do
      if value.name == :root or Enum.any?(agents, &(&1.name == value.name)),
        do: {:ok, value},
        else: Error.fail(:unknown_endpoint, [], "Unknown agent endpoint", value)
    end
  end

  defp endpoint(%{} = value, _agents, extensions) do
    if value in Extension.endpoints(extensions),
      do: {:ok, value},
      else:
        Error.fail(
          :unknown_endpoint,
          [],
          "Endpoint is not declared by a selected provider",
          value
        )
  end

  defp endpoint(_, _, _), do: Error.fail(:invalid_endpoint, [], "Expected a typed endpoint Map")

  defp delivery(%{delivery: delivery} = connection, agents)
       when delivery in [:single, :broadcast] do
    member =
      if connection.to.kind == :agent, do: Enum.find(agents, &(&1.name == connection.to.name))

    if (delivery == :single and member) && member.count != 1,
      do:
        Error.fail(
          :counted_delivery,
          :delivery,
          "A counted destination requires explicit :broadcast"
        ),
      else: :ok
  end

  defp delivery(_, _),
    do: Error.fail(:invalid_delivery, :delivery, "Expected :single or :broadcast")

  defp compatibility(definition, opts) do
    if Keyword.get(opts, :related?, true) do
      with {:ok, _} <- Error.at(checks(definition, opts), :connections), do: :ok
    else
      :ok
    end
  end

  @doc "Reports connection proofs. Unknown contracts remain :unchecked."
  def checks(definition, opts \\ []) do
    Data.list(definition.topology.connections, fn connection ->
      check(connection, definition, opts)
    end)
  end

  defp check(connection, definition, opts) do
    with {:ok, source} <- endpoint_definition(connection.from, definition, opts),
         {:ok, destination} <- endpoint_definition(connection.to, definition, opts) do
      if Data.wildcard?(connection.path) do
        {:ok, %{connection: connection, status: :unchecked, reason: :wildcard_coverage}}
      else
        with :ok <- accepted(destination, connection.path),
             {:ok, status} <- produced(source, connection.path) do
          {:ok,
           %{
             connection: connection,
             status: status,
             reason: if(status == :unchecked, do: :unknown_outputs, else: nil)
           }}
        end
      end
    end
  end

  defp endpoint_definition(%{kind: :agent, name: :root}, definition, _), do: {:ok, definition}

  defp endpoint_definition(%{kind: :agent, name: name}, definition, opts) do
    member = Enum.find(definition.topology.agents, &(&1.name == name))
    related(member.definition, opts)
  end

  defp endpoint_definition(_, _, _), do: {:ok, :provider}
  defp accepted(:provider, _), do: :ok

  defp accepted(destination, type) do
    case Route.select(destination, type) do
      {:ok, _} ->
        :ok

      {:error, _} ->
        Error.fail(:unaccepted_type, :to, "Destination does not accept the connection type", %{
          type: type,
          definition: destination.name
        })
    end
  end

  defp produced(:provider, _), do: {:ok, :unchecked}

  defp produced(source, type) do
    {types, unknown?} =
      Enum.reduce(source.routes, {[], false}, fn route, {types, unknown?} ->
        cond do
          route.handler.kind == :pass_through and not Data.wildcard?(route.path) ->
            {[route.path | types], unknown?}

          route.emits == nil ->
            {types, true}

          true ->
            {route.emits ++ types, unknown?}
        end
      end)

    cond do
      type in types ->
        {:ok, :compatible}

      unknown? ->
        {:ok, :unchecked}

      true ->
        Error.fail(
          :unproduced_type,
          :from,
          "Source contracts do not permit this connection type",
          %{type: type, definition: source.name}
        )
    end
  end

  @doc "Selects all declared output connections for one logical source and type."
  def connections_for(definition, from, type) do
    with :ok <- Data.exact(type) do
      {:ok,
       Enum.filter(definition.topology.connections, fn edge ->
         edge.from == from and Data.matches?(type, edge.path)
       end)}
    end
  end

  @doc "Binds member inputs from one parent state snapshot. It starts no processes."
  def bind(definition, state) do
    Data.list(definition.topology.agents, fn member ->
      with {:ok, child} <- related(member.definition, []),
           {:ok, count} <- resolve_ref(member.count, state),
           :ok <- Error.at(Data.positive(count), :count),
           {:ok, initial} <- resolve_ref(member.initial_state, state),
           {:ok, schema} <- Jido.Agent.Validation.state_schema(child),
           {:ok, child_state} <- Error.at(Data.initialize(schema, initial), :initial_state),
           {:ok, _} <- bind(child, child_state) do
        {:ok, %{name: member.name, definition: child, count: count, state: child_state}}
      end
    end)
    |> Error.at([:topology, :agents])
  end

  defp resolve_ref(%{kind: :state, key: key}, state) do
    case Map.fetch(state, key) do
      {:ok, value} -> {:ok, value}
      :error -> Error.fail(:missing_state_field, [], "State reference has no value", %{key: key})
    end
  end

  defp resolve_ref(value, state) when is_map(value) and not is_struct(value) do
    with {:ok, pairs} <-
           Data.list(Map.to_list(value), fn {key, v} ->
             with {:ok, v} <- resolve_ref(v, state), do: {:ok, {key, v}}
           end),
         do: {:ok, Map.new(pairs)}
  end

  defp resolve_ref(value, state) when is_list(value),
    do: Data.list(value, &resolve_ref(&1, state))

  defp resolve_ref(value, _), do: {:ok, value}
end
