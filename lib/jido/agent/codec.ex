defmodule Jido.Agent.Codec do
  @moduledoc """
  Reads and writes portable Agent definition documents.

  A document contains authoring data only. It does not contain an Agent ID,
  live state, process data, or runtime Plugin state. Code and schemas use
  stable IDs from a trusted `Jido.Authoring.Registry`.

  Decode does not start an Agent. It validates the complete definition through
  `Jido.Agent.define/1`.
  """

  alias Jido.Agent
  alias Jido.Agent.{Authoring, Error}
  alias Jido.Agent.Codec.Registry, as: AgentRegistry
  alias Jido.Authoring.{Document, Registry, Value}

  @fields ~w(module name description vsn schema metadata signal_source routes topology extensions)a
  @field_names Enum.map(@fields, &Atom.to_string/1)
  @reference_kinds [:agent, :action, :flow, :plugin, :extension, :transform, :schema]

  @type document :: %{required(String.t()) => term()}

  @doc "Writes one portable Agent definition with application-owned Registry IDs."
  @spec encode(Agent.t() | module() | map(), Registry.t() | map()) ::
          {:ok, document()} | {:error, term()}
  def encode(source, registry) do
    with {:ok, definition} <- definition(source),
         {:ok, registry} <- AgentRegistry.new(registry),
         {:ok, fields} <- encode_fields(definition, registry),
         document = %{
           "type" => "jido.agent.definition",
           "version" => 1,
           "definition" => fields
         },
         :ok <- Document.check(document) do
      {:ok, document}
    end
  end

  @doc "Reads one portable Agent definition through a trusted Registry."
  @spec decode(document(), Registry.t() | map()) :: {:ok, Agent.definition()} | {:error, term()}
  def decode(document, registry) do
    with :ok <- Document.check(document),
         :ok <- object(document, ~w(type version definition)),
         :ok <- document_version(document),
         {:ok, registry} <- AgentRegistry.new(registry),
         {:ok, fields} <- decode_fields(document["definition"], registry) do
      Agent.define(fields)
    end
  end

  @doc "Reads one portable Agent definition from JSON."
  @spec from_json(String.t(), Registry.t() | map()) ::
          {:ok, Agent.definition()} | {:error, term()}
  def from_json(json, registry) when is_binary(json) and byte_size(json) <= 8_388_608 do
    case Jason.decode(json) do
      {:ok, document} -> decode(document, registry)
      {:error, _reason} -> Error.fail(:invalid_json, [], "Invalid Agent definition JSON")
    end
  end

  def from_json(_json, _registry),
    do: Error.fail(:invalid_json, [], "Expected a JSON string of at most 8 MiB")

  defp document_version(%{"type" => "jido.agent.definition", "version" => 1}), do: :ok

  defp document_version(_document),
    do: Error.fail(:document_version, [], "Unknown Agent definition document type or version")

  defp definition(%Agent{} = agent) do
    with {:ok, agent} <- Agent.validate(agent) do
      agent
      |> Agent.definition()
      |> Map.from_struct()
      |> Agent.define()
    end
  end

  defp definition(map) when is_map(map) and not is_struct(map), do: Agent.define(map)
  defp definition(module) when is_atom(module), do: Jido.Agent.Validation.resolve(module)

  defp definition(_source),
    do: Error.fail(:invalid_definition, [], "Expected an Agent definition, instance, or module")

  defp encode_fields(agent, registry) do
    with {:ok, module} <- optional_reference(agent.module, registry, [:agent]),
         {:ok, schema} <- reference(agent.schema, registry, [:schema]),
         {:ok, metadata} <- Value.encode(agent.metadata, registry),
         {:ok, routes} <- encode_list(agent.routes, &encode_route(&1, registry)),
         {:ok, topology} <- encode_topology(agent.topology, registry),
         {:ok, extensions} <- encode_list(agent.extensions, &encode_extension(&1, registry)) do
      {:ok,
       %{
         "module" => module,
         "name" => agent.name,
         "description" => agent.description,
         "vsn" => agent.vsn,
         "schema" => schema,
         "metadata" => metadata,
         "signal_source" => agent.signal_source,
         "routes" => routes,
         "topology" => topology,
         "extensions" => extensions
       }}
    end
  end

  defp decode_fields(fields, registry) do
    with :ok <- object(fields, @field_names),
         {:ok, module} <- optional_resolve(fields["module"], registry, :agent),
         {:ok, schema} <- resolve(fields["schema"], registry, :schema),
         {:ok, metadata} <- Value.decode(fields["metadata"], registry),
         {:ok, routes} <- decode_list(fields["routes"], &decode_route(&1, registry)),
         {:ok, topology} <- decode_topology(fields["topology"], registry),
         {:ok, extensions} <-
           decode_list(fields["extensions"], &decode_extension(&1, registry)) do
      {:ok,
       %{
         module: module,
         name: fields["name"],
         description: fields["description"],
         vsn: fields["vsn"],
         schema: schema,
         metadata: metadata,
         signal_source: fields["signal_source"],
         routes: routes,
         topology: topology,
         extensions: extensions
       }}
    end
  end

  defp encode_route(route, registry) do
    with {:ok, helper} <- Value.encode(route.as, registry),
         {:ok, defaults} <- Value.encode(route.defaults, registry),
         {:ok, handler} <- encode_handler(route.handler, registry) do
      {:ok,
       %{
         "path" => route.path,
         "as" => helper,
         "defaults" => defaults,
         "handler" => handler,
         "emits" => route.emits
       }}
    end
  end

  defp decode_route(route, registry) do
    with :ok <- object(route, ~w(path as defaults handler emits)),
         {:ok, helper} <- Value.decode(route["as"], registry),
         {:ok, defaults} <- Value.decode(route["defaults"], registry),
         {:ok, handler} <- decode_handler(route["handler"], registry) do
      {:ok,
       %{
         path: route["path"],
         as: helper,
         defaults: defaults,
         handler: handler,
         emits: route["emits"]
       }}
    end
  end

  defp encode_handler(%{kind: kind, target: target}, registry)
       when kind in [:action, :flow, :transform] do
    with {:ok, target} <- reference(target, registry, [kind]),
         do: {:ok, %{"kind" => Atom.to_string(kind), "target" => target}}
  end

  defp encode_handler(%{kind: :pass_through}, _registry),
    do: {:ok, %{"kind" => "pass_through"}}

  defp encode_handler(_handler, _registry),
    do: Error.fail(:invalid_handler, [], "Agent definition contains an invalid route handler")

  defp decode_handler(%{"kind" => kind, "target" => target} = handler, registry)
       when map_size(handler) == 2 and kind in ["action", "flow", "transform"] do
    kind = String.to_existing_atom(kind)

    with {:ok, target} <- resolve(target, registry, kind),
         do: {:ok, %{kind: kind, target: target}}
  end

  defp decode_handler(%{"kind" => "pass_through"} = handler, _registry)
       when map_size(handler) == 1,
       do: {:ok, %{kind: :pass_through}}

  defp decode_handler(_handler, _registry),
    do: Error.fail(:invalid_document, [], "Invalid Agent definition route handler")

  defp encode_topology(%{agents: agents, connections: connections}, registry) do
    with {:ok, agents} <- encode_list(agents, &encode_member(&1, registry)),
         {:ok, connections} <- encode_list(connections, &encode_connection(&1, registry)) do
      {:ok, %{"agents" => agents, "connections" => connections}}
    end
  end

  defp encode_topology(_topology, _registry),
    do: Error.fail(:invalid_topology, [], "Agent definition contains an invalid topology")

  defp decode_topology(topology, registry) do
    with :ok <- object(topology, ~w(agents connections)),
         {:ok, agents} <- decode_list(topology["agents"], &decode_member(&1, registry)),
         {:ok, connections} <-
           decode_list(topology["connections"], &decode_connection(&1, registry)) do
      {:ok, %{agents: agents, connections: connections}}
    end
  end

  defp encode_member(member, registry) do
    with {:ok, name} <- Value.encode(member.name, registry),
         {:ok, definition} <- encode_nested_definition(member.definition, registry),
         {:ok, count} <- Value.encode(member.count, registry),
         {:ok, initial_state} <- Value.encode(member.initial_state, registry) do
      encoded = %{
        "name" => name,
        "definition" => definition,
        "count" => count,
        "initial_state" => initial_state
      }

      if Map.has_key?(member, :identities) do
        with {:ok, identities} <- Value.encode(member.identities, registry),
             do: {:ok, Map.put(encoded, "identities", identities)}
      else
        {:ok, encoded}
      end
    end
  end

  defp decode_member(member, registry) do
    with :ok <- object(member, ~w(name definition count initial_state), ~w(identities)),
         {:ok, name} <- Value.decode(member["name"], registry),
         {:ok, definition} <- decode_nested_definition(member["definition"], registry),
         {:ok, count} <- Value.decode(member["count"], registry),
         {:ok, initial_state} <- Value.decode(member["initial_state"], registry) do
      decoded = %{
        name: name,
        definition: definition,
        count: count,
        initial_state: initial_state
      }

      if Map.has_key?(member, "identities") do
        with {:ok, identities} <- Value.decode(member["identities"], registry),
             do: {:ok, Map.put(decoded, :identities, identities)}
      else
        {:ok, decoded}
      end
    end
  end

  defp encode_nested_definition(%Agent{} = definition, registry) do
    with {:ok, fields} <- encode_fields(definition, registry),
         do: {:ok, %{"$type" => "agent_definition", "value" => fields}}
  end

  defp encode_nested_definition(module, registry) when is_atom(module),
    do: reference(module, registry, [:agent])

  defp encode_nested_definition(_definition, _registry),
    do: Error.fail(:invalid_definition, [], "Invalid nested Agent definition")

  defp decode_nested_definition(
         %{"$type" => "agent_definition", "value" => fields} = value,
         registry
       )
       when map_size(value) == 2 do
    with {:ok, fields} <- decode_fields(fields, registry), do: Agent.define(fields)
  end

  defp decode_nested_definition(value, registry), do: resolve(value, registry, :agent)

  defp encode_connection(connection, registry) do
    with {:ok, from} <- Value.encode(connection.from, registry),
         {:ok, to} <- Value.encode(connection.to, registry) do
      {:ok,
       %{
         "path" => connection.path,
         "from" => from,
         "to" => to,
         "delivery" => Atom.to_string(connection.delivery)
       }}
    end
  end

  defp decode_connection(connection, registry) do
    with :ok <- object(connection, ~w(path from to delivery)),
         {:ok, from} <- Value.decode(connection["from"], registry),
         {:ok, to} <- Value.decode(connection["to"], registry),
         {:ok, delivery} <- delivery(connection["delivery"]) do
      {:ok, %{path: connection["path"], from: from, to: to, delivery: delivery}}
    end
  end

  defp delivery("single"), do: {:ok, :single}
  defp delivery("broadcast"), do: {:ok, :broadcast}
  defp delivery(_value), do: Error.fail(:invalid_document, [], "Invalid Agent delivery value")

  defp encode_extension(extension, registry) do
    with {:ok, provider} <- reference(extension.provider, registry, [:extension, :plugin]),
         {:ok, data} <- Value.encode(extension.data, registry) do
      {:ok,
       %{
         "id" => extension.id,
         "provider" => provider,
         "vsn" => extension.vsn,
         "data" => data
       }}
    end
  end

  defp decode_extension(extension, registry) do
    with :ok <- object(extension, ~w(id provider vsn data)),
         {:ok, provider} <- resolve_one(extension["provider"], registry, [:extension, :plugin]),
         {:ok, data} <- Value.decode(extension["data"], registry) do
      {:ok,
       %{
         id: extension["id"],
         provider: provider,
         vsn: extension["vsn"],
         data: data
       }}
    end
  end

  defp optional_reference(nil, _registry, _kinds), do: {:ok, nil}
  defp optional_reference(value, registry, kinds), do: reference(value, registry, kinds)

  defp optional_resolve(nil, _registry, _kind), do: {:ok, nil}
  defp optional_resolve(value, registry, kind), do: resolve(value, registry, kind)

  defp reference(value, registry, kinds) do
    Enum.reduce_while(kinds, no_identifier(kinds), fn kind, _error ->
      case Registry.identifier(registry, kind, value) do
        {:ok, identifier} ->
          {:halt,
           {:ok,
            %{
              "$type" => "reference",
              "kind" => Atom.to_string(kind),
              "id" => identifier
            }}}

        {:error, _exception} ->
          {:cont, no_identifier(kinds)}
      end
    end)
  end

  defp no_identifier(kinds),
    do:
      Error.fail(:unknown_reference, [], "Agent Registry has no identifier for a value", %{
        kinds: kinds
      })

  defp resolve(
         %{"$type" => "reference", "kind" => kind_name, "id" => identifier} = value,
         registry,
         kind
       )
       when map_size(value) == 3 and kind in @reference_kinds do
    if kind_name == Atom.to_string(kind),
      do: Registry.resolve(registry, identifier, kind),
      else: Error.fail(:unknown_reference_kind, [], "Agent Registry reference has the wrong kind")
  end

  defp resolve(_value, _registry, _kind),
    do: Error.fail(:invalid_document, [], "Invalid Agent Registry reference")

  defp resolve_one(value, registry, kinds) do
    Enum.reduce_while(
      kinds,
      Error.fail(:unknown_reference_kind, [], "Invalid Agent reference"),
      fn
        kind, _error ->
          case resolve(value, registry, kind) do
            {:ok, resolved} -> {:halt, {:ok, resolved}}
            {:error, _exception} = error -> {:cont, error}
          end
      end
    )
  end

  defp encode_list(values, encoder) when is_list(values),
    do: Authoring.traverse(values, encoder)

  defp encode_list(_values, _encoder),
    do: Error.fail(:invalid_list, [], "Expected a proper Agent definition list")

  defp decode_list(values, decoder) when is_list(values),
    do: Authoring.traverse(values, decoder)

  defp decode_list(_values, _decoder),
    do: Error.fail(:invalid_document, [], "Expected an Agent definition list")

  defp object(value, fields) when is_map(value) and not is_struct(value) do
    if Enum.sort(Map.keys(value)) == Enum.sort(fields),
      do: :ok,
      else: Error.fail(:invalid_document, [], "Unknown or missing Agent document fields")
  end

  defp object(_value, _fields),
    do: Error.fail(:invalid_document, [], "Agent document object must be a map")

  defp object(value, required, optional) when is_map(value) and not is_struct(value) do
    keys = Map.keys(value)

    if required -- keys == [] and keys -- (required ++ optional) == [],
      do: :ok,
      else: Error.fail(:invalid_document, [], "Unknown or missing Agent document fields")
  end

  defp object(_value, _required, _optional),
    do: Error.fail(:invalid_document, [], "Agent document object must be a map")
end
