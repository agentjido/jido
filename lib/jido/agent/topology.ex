defmodule Jido.Agent.Topology do
  alias Jido.Joi
  @moduledoc "Logical members and output connections. These declarations do not start processes."
  alias Jido.Agent.{Extension, Plugin, Route, Schema}
  alias Jido.Error

  @type state_reference :: %{kind: :state, key: atom()}
  @type endpoint :: map()
  @type connection :: map()
  @type check :: %{
          connection: connection(),
          status: :compatible | :unchecked,
          reason: nil | :wildcard_coverage | :unknown_outputs
        }
  @type bound_member :: %{
          name: atom(),
          definition: map(),
          count: pos_integer(),
          state: map()
        }

  @doc "Creates a symbolic reference to one parent Agent state field."
  @spec state(atom()) :: state_reference()
  def state(key), do: %{kind: :state, key: key}

  @doc false
  def empty?(%{agents: [], connections: []}), do: true
  def empty?(_), do: false

  # Persist slot identities with the logical topology. A removed slot loses
  # its identity, so a later slot with the same number starts a new lifetime.
  @doc false
  def identify(before, candidate, resolver) when is_function(resolver, 2) do
    with {:ok, desired} <- bind(candidate, candidate.state, resolver),
         {:ok, previous} <- previous_members(before, resolver) do
      members =
        Enum.map(candidate.topology.agents, fn declaration ->
          member = Enum.find(desired, &(&1.name == declaration.name))
          old = Enum.find(previous, &(&1.name == member.name))
          same? = old && old.definition == member.definition && old.state == member.state

          retained =
            cond do
              same? ->
                before.topology.agents
                |> Enum.find(&(&1.name == member.name))
                |> Map.get(:identities, %{})

              is_nil(before) ->
                Map.get(declaration, :identities, %{})

              true ->
                %{}
            end

          identities =
            Map.new(1..member.count, fn slot ->
              identity =
                if is_nil(before) or (same? && slot <= old.count),
                  do: Map.get(retained, slot, "initial"),
                  else: Jido.Id.uuid7()

              {slot, identity}
            end)

          Map.put(declaration, :identities, identities)
        end)

      {:ok, put_in(candidate.topology.agents, members)}
    end
  end

  # These checks have no enclosing Agent. Full reference and contract checks
  # run when the complete candidate Agent is validated.
  @doc false
  def validate(value) do
    with {:ok, value} <-
           Schema.fields(value, [:agents, :connections], %{agents: [], connections: []}),
         {:ok, agents} <- Error.prefix_result_path(Schema.list(value.agents, &entry(:agent, &1)), :agents),
         {:ok, connections} <-
           Error.prefix_result_path(Schema.list(value.connections, &entry(:connect, &1)), :connections),
         do: {:ok, %{agents: agents, connections: connections}}
  end

  @doc false
  def entry(:agent, value) do
    with {:ok, value} <-
           Schema.fields(value, [:name, :definition, :count, :initial_state, :identities], %{
             count: 1,
             initial_state: %{}
           }),
         :ok <- Error.prefix_result_path(Schema.name(value[:name]), :name),
         :ok <- identities(Map.get(value, :identities, %{})),
         true <- Map.has_key?(value, :definition) do
      {:ok, value}
    else
      false -> Error.validation_result(:invalid_member, :definition, "Expected an Agent definition or module")
      error -> error
    end
  end

  def entry(:connect, value) do
    with {:ok, value} <- Schema.fields(value, [:path, :from, :to, :delivery], %{delivery: :single}),
         :ok <- Error.prefix_result_path(Schema.path(value[:path]), :path),
         :ok <- Error.prefix_result_path(Schema.plain_map(value[:from]), :from),
         :ok <- Error.prefix_result_path(Schema.plain_map(value[:to]), :to),
         do: {:ok, value}
  end

  defp identities(value) when is_map(value) and not is_struct(value) do
    if Enum.all?(value, fn {slot, id} ->
         is_integer(slot) and slot > 0 and is_binary(id) and byte_size(id) > 0
       end),
       do: :ok,
       else: Error.validation_result(:invalid_member_identity, :identities, "Expected positive slots and IDs")
  end

  defp identities(_),
    do: Error.validation_result(:invalid_member_identity, :identities, "Expected a member identity Map")

  @doc false
  def normalize(value, parent, opts, resolver) when is_function(resolver, 2) do
    with {:ok, topology} <-
           Schema.fields(value, [:agents, :connections], %{agents: [], connections: []}),
         {:ok, agents} <-
           Error.prefix_result_path(
             Schema.list(topology.agents, &member(&1, parent, opts, resolver)),
             :agents
           ),
         :ok <- Error.prefix_result_path(Schema.unique(agents, & &1.name), :agents),
         {:ok, connections} <-
           Error.prefix_result_path(
             Schema.list(topology.connections, &connection(&1, agents, parent.plugins)),
             :connections
           ),
         :ok <- Error.prefix_result_path(Schema.unique(connections, &{&1.from, &1.to, &1.path}), :connections),
         topology = %{agents: agents, connections: connections},
         :ok <- compatibility(%{parent | topology: topology}, opts, resolver) do
      {:ok, topology}
    end
  end

  defp member(value, parent, opts, resolver) do
    with {:ok, member} <- entry(:agent, value),
         :ok <- reserved(member.name),
         :ok <- Error.prefix_result_path(count(member.count, parent.schema), :count),
         :ok <- Error.prefix_result_path(Schema.plain_map(member.initial_state), :initial_state),
         :ok <- Error.prefix_result_path(references(member.initial_state, parent.schema), :initial_state),
         {:ok, definition} <- nested(member[:definition], opts, resolver),
         member = Map.put(member, :definition, definition),
         :ok <- initial(member, opts, resolver) do
      {:ok, member}
    end
  end

  defp reserved(:root),
    do: Error.validation_result(:reserved_name, :name, "The :root name belongs to the enclosing agent")

  defp reserved(_), do: :ok
  defp count(%{kind: :state} = ref, schema), do: reference(ref, schema)
  defp count(value, _), do: Schema.positive(value)

  defp reference(value, schema) do
    with {:ok, ref} <- Schema.fields(value, [:kind, :key]), :ok <- Schema.name(ref[:key]) do
      if Keyword.has_key?(schema.fields, ref.key),
        do: :ok,
        else:
          Error.validation_result(:unknown_state_field, [], "Parent state field does not exist", %{
            key: ref.key
          })
    end
  end

  defp references(%{kind: :state} = value, schema), do: reference(value, schema)

  defp references(value, schema) when is_map(value) and not is_struct(value) do
    with {:ok, _} <-
           Schema.list(Map.to_list(value), fn {key, v} ->
             with :ok <- Error.prefix_result_path(references(v, schema), key), do: {:ok, v}
           end),
         do: :ok
  end

  defp references(value, schema) when is_list(value) do
    with {:ok, _} <- Schema.list(value, fn v -> with :ok <- references(v, schema), do: {:ok, v} end),
         do: :ok
  end

  defp references(value, _), do: Schema.static(value)

  defp nested(value, opts, resolver) when is_map(value) do
    resolver.(value, opts)
  end

  defp nested(value, opts, resolver) when is_atom(value) and value not in [nil, true, false] do
    if Keyword.get(opts, :related?, true) do
      case related(value, opts, resolver) do
        {:ok, _} -> {:ok, value}
        error -> error
      end
    else
      {:ok, value}
    end
  end

  defp nested(_, _, _resolver),
    do: Error.validation_result(:invalid_member, :definition, "Expected an Agent definition or module")

  defp related(value, opts, resolver) when is_map(value), do: resolver.(value, opts)

  defp related(module, opts, resolver) do
    seen = Keyword.get(opts, :seen, [])

    cond do
      module in seen ->
        Error.validation_result(:recursive_membership, :definition, "Member containment cannot be cyclic", %{
          module: module
        })

      # definition/0 starts with an empty :seen, so a DSL module continues this walk instead.
      Code.ensure_loaded?(module) and function_exported?(module, :__jido_definition__, 1) ->
        module.__jido_definition__(related?: true, seen: [module | seen])

      Code.ensure_loaded?(module) and function_exported?(module, :definition, 0) ->
        resolver.(module.definition(), Keyword.put(opts, :seen, [module | seen]))

      true ->
        Error.validation_result(:unresolved_definition, :definition, "Member definition is not available", %{
          module: module
        })
    end
  end

  defp initial(member, opts, resolver) do
    if Keyword.get(opts, :related?, true) do
      with {:ok, child} <- related(member.definition, opts, resolver),
           {:ok, schema} <- state_schema(child),
           :ok <- partial_initial(schema, member.initial_state),
           do: :ok
    else
      :ok
    end
  end

  defp state_schema(agent),
    do: Plugin.compose_schema(agent.schema, Plugin.declarations(agent))

  defp partial_initial(schema, state) do
    partial_value(schema, state) |> Error.prefix_result_path(:initial_state)
  end

  # A symbolic value has no current value during authoring. Validate the known
  # parts and check the complete value again when an instance binds the input.
  defp partial_value(_schema, %{kind: :state}), do: :ok

  defp partial_value(schema, state) do
    cond do
      Joi.Schema.kind(schema) == :map and
        match?({:ok, fields} when is_list(fields), Joi.Schema.fields(schema)) and
        is_map(state) and not is_struct(state) ->
        partial_map(schema, state)

      Joi.Schema.kind(schema) == :array and is_list(state) ->
        partial_array(schema, state)

      true ->
        with {:ok, _} <- Schema.parse_value(schema, state), do: :ok
    end
  end

  defp partial_map(schema, state) do
    {:ok, fields} = Joi.Schema.fields(schema)
    known = Map.new(fields)

    with {:ok, _} <- Schema.fields(state, Map.keys(known)),
         {:ok, _} <-
           Schema.list(Map.to_list(state), fn {key, value} ->
             with :ok <- Error.prefix_result_path(partial_value(Map.fetch!(known, key), value), key),
                  do: {:ok, {key, value}}
           end),
         do: :ok
  end

  defp partial_array(schema, value) do
    {:ok, inner} = Joi.Schema.inner(schema)
    open_schema = Joi.Schema.put_inner(schema, Joi.any())

    with {:ok, _} <- Schema.parse_value(open_schema, value),
         {:ok, _} <-
           Schema.list(value, fn item -> with :ok <- partial_value(inner, item), do: {:ok, item} end),
         do: :ok
  end

  defp connection(value, agents, plugins) do
    with {:ok, connection} <- entry(:connect, value),
         {:ok, from} <- Error.prefix_result_path(endpoint(connection[:from], agents, plugins), :from),
         {:ok, to} <- Error.prefix_result_path(endpoint(connection[:to], agents, plugins), :to),
         connection = %{connection | from: from, to: to},
         :ok <- delivery(connection, agents),
         :ok <- Extension.verify_connection(plugins, connection),
         do: {:ok, connection}
  end

  defp endpoint(%{kind: :agent} = value, agents, _extensions) do
    with {:ok, value} <- Schema.fields(value, [:kind, :name]), :ok <- Schema.name(value[:name]) do
      if value.name == :root or Enum.any?(agents, &(&1.name == value.name)),
        do: {:ok, value},
        else: Error.validation_result(:unknown_endpoint, [], "Unknown agent endpoint", value)
    end
  end

  defp endpoint(%{} = value, _agents, plugins) do
    if value in Extension.endpoints(plugins),
      do: {:ok, value},
      else:
        Error.validation_result(
          :unknown_endpoint,
          [],
          "Endpoint is not declared by a selected provider",
          value
        )
  end

  defp endpoint(_, _, _), do: Error.validation_result(:invalid_endpoint, [], "Expected a typed endpoint Map")

  defp delivery(%{delivery: delivery} = connection, agents)
       when delivery in [:single, :broadcast] do
    member =
      if connection.to.kind == :agent, do: Enum.find(agents, &(&1.name == connection.to.name))

    if (delivery == :single and member) && member.count != 1,
      do:
        Error.validation_result(
          :counted_delivery,
          :delivery,
          "A counted destination requires explicit :broadcast"
        ),
      else: :ok
  end

  defp delivery(_, _),
    do: Error.validation_result(:invalid_delivery, :delivery, "Expected :single or :broadcast")

  defp compatibility(definition, opts, resolver) do
    if Keyword.get(opts, :related?, true) do
      with {:ok, _} <-
             Error.prefix_result_path(checks(definition, opts, resolver), :connections),
           do: :ok
    else
      :ok
    end
  end

  @doc "Reports connection proofs. Unknown contracts remain :unchecked."
  @spec checks(map(), keyword(), function()) :: {:ok, [check()]} | {:error, term()}
  def checks(definition, opts, resolver) when is_function(resolver, 2) do
    Schema.list(definition.topology.connections, fn connection ->
      check(connection, definition, opts, resolver)
    end)
  end

  defp check(connection, definition, opts, resolver) do
    with {:ok, source} <- endpoint_definition(connection.from, definition, opts, resolver),
         {:ok, destination} <- endpoint_definition(connection.to, definition, opts, resolver) do
      if Schema.wildcard?(connection.path) do
        {:ok, %{connection: connection, status: :unchecked, reason: :wildcard_coverage}}
      else
        with :ok <- accepted(destination, connection.path),
             :ok <- produced(source, connection.path) do
          {:ok,
           %{
             connection: connection,
             status: :unchecked,
             reason: :unknown_outputs
           }}
        end
      end
    end
  end

  defp endpoint_definition(%{kind: :agent, name: :root}, definition, _, _resolver),
    do: {:ok, definition}

  defp endpoint_definition(%{kind: :agent, name: name}, definition, opts, resolver) do
    member = Enum.find(definition.topology.agents, &(&1.name == name))
    related(member.definition, opts, resolver)
  end

  defp endpoint_definition(_, _, _, _resolver), do: {:ok, :provider}
  defp accepted(:provider, _), do: :ok

  defp accepted(destination, type) do
    case Route.select(destination, type) do
      {:ok, _} ->
        :ok

      {:error, _} ->
        Error.validation_result(:unaccepted_type, :to, "Destination does not accept the connection type", %{
          type: type,
          definition: destination.name
        })
    end
  end

  defp produced(:provider, _), do: :ok
  defp produced(_source, _type), do: :ok

  @doc "Selects all declared output connections for one logical source and type."
  @spec connections_for(map(), endpoint(), String.t()) ::
          {:ok, [connection()]} | {:error, term()}
  def connections_for(definition, from, type) do
    with :ok <- Schema.exact(type) do
      {:ok,
       Enum.filter(definition.topology.connections, fn edge ->
         edge.from == from and Schema.matches?(type, edge.path)
       end)}
    end
  end

  @doc "Binds member inputs from one parent state snapshot. It starts no processes."
  @spec bind(map(), map(), function()) :: {:ok, [bound_member()]} | {:error, term()}
  def bind(definition, state, resolver) when is_function(resolver, 2) do
    Schema.list(definition.topology.agents, fn member ->
      with {:ok, child} <- related(member.definition, [], resolver),
           {:ok, count} <- resolve_ref(member.count, state),
           :ok <- Error.prefix_result_path(Schema.positive(count), :count),
           {:ok, initial} <- resolve_ref(member.initial_state, state),
           {:ok, schema} <- state_schema(child),
           :ok <- partial_initial(schema, initial) do
        {:ok, %{name: member.name, definition: child, count: count, state: initial}}
      end
    end)
    |> Error.prefix_result_path([:topology, :agents])
  end

  defp resolve_ref(%{kind: :state, key: key}, state) do
    case Map.fetch(state, key) do
      {:ok, value} -> {:ok, value}
      :error -> Error.validation_result(:missing_state_field, [], "State reference has no value", %{key: key})
    end
  end

  defp resolve_ref(value, state) when is_map(value) and not is_struct(value) do
    with {:ok, pairs} <-
           Schema.list(Map.to_list(value), fn {key, v} ->
             with {:ok, v} <- resolve_ref(v, state), do: {:ok, {key, v}}
           end),
         do: {:ok, Map.new(pairs)}
  end

  defp resolve_ref(value, state) when is_list(value),
    do: Schema.list(value, &resolve_ref(&1, state))

  defp resolve_ref(value, _), do: {:ok, value}

  defp previous_members(nil, _resolver), do: {:ok, []}
  defp previous_members(agent, resolver), do: bind(agent, agent.state, resolver)
end
