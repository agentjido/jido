defmodule Jido.Agent.Codec do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Agent.{Authoring, Error, Extension}
  alias Jido.Authoring.{Issue, Registry, Value}

  @fields ~w(module name description vsn schema initial_state metadata signal_source routes topology extensions)a
  @field_names Enum.map(@fields, &Atom.to_string/1)
  @required_field_names @field_names -- ["initial_state"]
  @type document :: %{required(String.t()) => term()}

  @doc false
  def __jido_authoring_codec__,
    do: %{type: "jido.agent.definition", vsn: 1, encoder: Jido.Agent}

  @doc false
  def encode_document(source, registry) do
    with {:ok, definition} <- definition(source),
         {:ok, fields} <- encode_fields(definition, registry),
         document = %{
           "type" => "jido.agent.definition",
           "vsn" => 1,
           "definition" => fields
         } do
      {:ok, document}
    end
  end

  @doc false
  def decode_document(document, registry) do
    with :ok <- object(document, ~w(type vsn definition)),
         {:ok, fields} <- at(decode_fields(document["definition"], registry), ["definition"]),
         {:ok, agent} <- at(Agent.define(fields), ["definition"]) do
      {:ok, agent}
    else
      {:error, error} -> {:error, [authoring_issue(error)]}
    end
  end

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
         {:ok, schema} <- encode_reference(agent.schema, registry, [:schema]),
         {:ok, initial_state} <- Value.encode(agent.initial_state, registry),
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
         "initial_state" => initial_state,
         "metadata" => metadata,
         "signal_source" => agent.signal_source,
         "routes" => routes,
         "topology" => topology,
         "extensions" => extensions
       }}
    end
  end

  defp decode_fields(fields, registry) do
    with :ok <- object(fields, @required_field_names, ["initial_state"]),
         {:ok, module} <- at(optional_resolve(fields["module"], registry, :agent), ["module"]),
         {:ok, schema} <-
           at(Registry.decode_reference(registry, fields["schema"], :schema), ["schema"]),
         {:ok, initial_state} <- decode_initial_state(fields, registry),
         {:ok, metadata} <- at(Value.decode(fields["metadata"], registry), ["metadata"]),
         {:ok, routes} <-
           at(decode_list(fields["routes"], &decode_route(&1, registry)), ["routes"]),
         {:ok, topology} <- at(decode_topology(fields["topology"], registry), ["topology"]),
         {:ok, extensions} <-
           at(
             decode_list(fields["extensions"], &decode_extension(&1, registry)),
             ["extensions"]
           ) do
      {:ok,
       %{
         module: module,
         name: fields["name"],
         description: fields["description"],
         vsn: fields["vsn"],
         schema: schema,
         initial_state: initial_state,
         metadata: metadata,
         signal_source: fields["signal_source"],
         routes: routes,
         topology: topology,
         extensions: extensions
       }}
    end
  end

  defp decode_initial_state(fields, registry) do
    if Map.has_key?(fields, "initial_state"),
      do: at(Value.decode(fields["initial_state"], registry), ["initial_state"]),
      else: {:ok, %{}}
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
         {:ok, helper} <- at(Value.decode(route["as"], registry), ["as"]),
         {:ok, defaults} <- at(Value.decode(route["defaults"], registry), ["defaults"]),
         {:ok, handler} <- at(decode_handler(route["handler"], registry), ["handler"]) do
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
    with {:ok, target} <- encode_reference(target, registry, kind),
         do: {:ok, %{"kind" => Atom.to_string(kind), "target" => target}}
  end

  defp encode_handler(%{kind: :pass_through}, _registry),
    do: {:ok, %{"kind" => "pass_through"}}

  defp encode_handler(_handler, _registry),
    do: Error.fail(:invalid_handler, [], "Agent definition contains an invalid route handler")

  defp decode_handler(%{"kind" => kind, "target" => target} = handler, registry)
       when map_size(handler) == 2 and kind in ["action", "flow", "transform"] do
    kind = String.to_existing_atom(kind)

    with {:ok, target} <- at(Registry.decode_reference(registry, target, kind), ["target"]),
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
         {:ok, agents} <-
           at(decode_list(topology["agents"], &decode_member(&1, registry)), ["agents"]),
         {:ok, connections} <-
           at(
             decode_list(topology["connections"], &decode_connection(&1, registry)),
             ["connections"]
           ) do
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
         {:ok, name} <- at(Value.decode(member["name"], registry), ["name"]),
         {:ok, definition} <-
           at(decode_nested_definition(member["definition"], registry), ["definition"]),
         {:ok, count} <- at(Value.decode(member["count"], registry), ["count"]),
         {:ok, initial_state} <-
           at(Value.decode(member["initial_state"], registry), ["initial_state"]) do
      decoded = %{
        name: name,
        definition: definition,
        count: count,
        initial_state: initial_state
      }

      if Map.has_key?(member, "identities") do
        with {:ok, identities} <-
               at(Value.decode(member["identities"], registry), ["identities"]),
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
    do: encode_reference(module, registry, :agent)

  defp encode_nested_definition(_definition, _registry),
    do: Error.fail(:invalid_definition, [], "Invalid nested Agent definition")

  defp decode_nested_definition(
         %{"$type" => "agent_definition", "value" => fields} = value,
         registry
       )
       when map_size(value) == 2 do
    with {:ok, fields} <- at(decode_fields(fields, registry), ["value"]),
         do: at(Agent.define(fields), ["value"])
  end

  defp decode_nested_definition(value, registry),
    do: Registry.decode_reference(registry, value, :agent)

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
         {:ok, from} <- at(Value.decode(connection["from"], registry), ["from"]),
         {:ok, to} <- at(Value.decode(connection["to"], registry), ["to"]),
         {:ok, delivery} <- at(delivery(connection["delivery"]), ["delivery"]) do
      {:ok, %{path: connection["path"], from: from, to: to, delivery: delivery}}
    end
  end

  defp delivery("single"), do: {:ok, :single}
  defp delivery("broadcast"), do: {:ok, :broadcast}
  defp delivery(_value), do: Error.fail(:invalid_document, [], "Invalid Agent delivery value")

  defp encode_extension(extension, registry) do
    with {:ok, provider} <-
           encode_reference(extension.provider, registry, [:extension, :plugin]),
         {:ok, data} <-
           Extension.encode_authoring_data(extension.provider, extension.data, registry) do
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
         {:ok, provider} <-
           at(
             Registry.decode_reference(
               registry,
               extension["provider"],
               [:extension, :plugin]
             ),
             ["provider"]
           ),
         {:ok, data} <-
           at(
             Extension.decode_authoring_data(provider, extension["data"], registry),
             ["data"]
           ) do
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

  defp optional_reference(value, registry, kinds),
    do: encode_reference(value, registry, kinds)

  defp optional_resolve(nil, _registry, _kind), do: {:ok, nil}

  defp optional_resolve(value, registry, kind),
    do: Registry.decode_reference(registry, value, kind)

  defp encode_reference(value, registry, kinds) do
    case Registry.encode_reference(registry, kinds, value) do
      {:ok, reference} ->
        {:ok, reference}

      {:error, %Registry.Error{}} ->
        Error.fail(:unknown_reference, [], "Agent Registry has no reference for a value", %{
          kinds: List.wrap(kinds)
        })
    end
  end

  defp encode_list(values, encoder) when is_list(values),
    do: Authoring.traverse(values, encoder)

  defp encode_list(_values, _encoder),
    do: Error.fail(:invalid_list, [], "Expected a proper Agent definition list")

  defp decode_list(values, decoder) when is_list(values) do
    values
    |> Enum.with_index()
    |> Authoring.traverse(fn {value, index} -> at(decoder.(value), [index]) end)
  end

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

  defp authoring_issue(%Issue{} = issue), do: issue

  defp authoring_issue(%Registry.Error{} = error) do
    path =
      error.details
      |> Map.get(:path, [])
      |> Enum.map(&json_path_segment/1)

    path =
      case error.details do
        %{field: field} when is_binary(field) -> path ++ [field]
        _other -> path
      end

    Issue.new(:reference, path, Exception.message(error), details: error.details)
  end

  defp authoring_issue(%Value.Error{} = error),
    do:
      Issue.new(
        error.reason,
        Enum.map(error.path, &json_path_segment/1),
        Exception.message(error),
        details: error.details
      )

  defp authoring_issue(error), do: authoring_issue(error, [])

  defp authoring_issue(error, prefix) do
    details = if is_map(error) and is_map(Map.get(error, :details)), do: error.details, else: %{}

    path =
      if is_map(error),
        do: prefix ++ Enum.map(Map.get(error, :path, []), &json_path_segment/1),
        else: prefix

    code =
      if is_map(error), do: Map.get(error, :code) || :invalid_document, else: :invalid_document

    message =
      if is_map(error) and Map.get(error, :__exception__),
        do: Exception.message(error),
        else: inspect(error)

    Issue.new(code, path, message, details: details)
  end

  defp at({:error, error}, path),
    do: {:error, prefix_issue(authoring_issue(error), path)}

  defp at(result, _path), do: result

  defp prefix_issue(%Issue{} = issue, path), do: %{issue | path: path ++ issue.path}

  defp json_path_segment(segment) when is_atom(segment), do: Atom.to_string(segment)
  defp json_path_segment(segment), do: segment
end
