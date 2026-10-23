defmodule Jido.Agent.Codec do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Agent.{Authoring, Error, Extension}
  alias Jido.Authoring.{Issue, Registry, Value}

  @type document :: %{required(String.t()) => term()}

  @doc false
  def __jido_authoring_codec__,
    do: %{type: "jido.agent.definition", vsn: 1, encoder: Jido.Agent}

  @doc false
  def encode_document(source, registry) do
    with {:ok, definition} <- definition(source),
         {:ok, fields} <- encode_fields(definition, registry) do
      {:ok, %{"type" => "jido.agent.definition", "vsn" => 1, "definition" => fields}}
    end
  end

  @doc false
  def decode_document(document, registry) do
    with :ok <- object(document, ~w(type vsn definition)),
         :ok <- document_version(document),
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
    encode_map(agent,
      module: &optional_reference(&1, registry, [:agent]),
      schema: &encode_reference(&1, registry, [:schema]),
      initial_state: &Value.encode(&1, registry),
      metadata: &Value.encode(&1, registry),
      routes: &encode_list(&1, fn route -> encode_route(route, registry) end),
      topology: &encode_topology(&1, registry),
      extensions: &encode_list(&1, fn extension -> encode_extension(extension, registry) end),
      name: nil,
      description: nil,
      vsn: nil,
      signal_source: nil
    )
  end

  defp decode_fields(fields, registry) do
    decode_map(
      fields,
      [
        module: &optional_resolve(&1, registry, :agent),
        schema: &Registry.decode_reference(registry, &1, :schema),
        initial_state: fn value ->
          if Map.has_key?(fields, "initial_state"),
            do: Value.decode(value, registry),
            else: {:ok, %{}}
        end,
        metadata: &Value.decode(&1, registry),
        routes: &decode_list(&1, fn route -> decode_route(route, registry) end),
        topology: &decode_topology(&1, registry),
        extensions: &decode_list(&1, fn extension -> decode_extension(extension, registry) end),
        name: nil,
        description: nil,
        vsn: nil,
        signal_source: nil
      ],
      [:initial_state]
    )
  end

  @doc false
  def encode_route(route, registry, reference \\ &encode_reference/3) do
    encode_map(route,
      as: &Value.encode(&1, registry),
      defaults: &Value.encode(&1, registry),
      handler: &encode_handler(&1, registry, reference),
      state: &{:ok, encode_state(&1)},
      reply: &{:ok, encode_reply(&1)},
      path: nil
    )
  end

  defp decode_route(route, registry) do
    decode_map(route,
      as: &Value.decode(&1, registry),
      defaults: &Value.decode(&1, registry),
      handler: &decode_handler(&1, registry),
      state: &decode_state/1,
      reply: &decode_reply/1,
      path: nil
    )
  end

  defp encode_state(:unchanged), do: "unchanged"
  defp encode_state(selector), do: encode_selector(selector)

  defp decode_state("unchanged"), do: {:ok, :unchanged}
  defp decode_state(selector), do: decode_selector(selector)

  defp encode_reply(nil), do: nil

  defp encode_reply(%{type: type, from: from}),
    do: %{"type" => type, "from" => encode_selector(from)}

  defp decode_reply(nil), do: {:ok, nil}

  defp decode_reply(reply) do
    with :ok <- object(reply, ~w(type from)),
         true <- is_binary(reply["type"]),
         {:ok, from} <- at(decode_selector(reply["from"]), ["from"]) do
      {:ok, %{type: reply["type"], from: from}}
    else
      false -> Error.fail(:invalid_document, ["type"], "Invalid Agent route reply type")
      error -> error
    end
  end

  defp encode_selector(%{source: :output, path: path}),
    do: %{"source" => "output", "path" => Enum.map(path, &to_string/1)}

  defp decode_selector(selector) do
    with :ok <- object(selector, ~w(source path)),
         true <- selector["source"] == "output",
         {:ok, path} <- decode_selector_path(selector["path"]) do
      {:ok, %{source: :output, path: path}}
    else
      false -> Error.fail(:invalid_document, ["source"], "Invalid output selector source")
      error -> error
    end
  end

  defp decode_selector_path(path) when is_list(path) do
    if Enum.all?(path, &is_binary/1),
      do: {:ok, path},
      else: Error.fail(:invalid_document, ["path"], "Output selector path keys must be strings")
  end

  defp decode_selector_path(_path),
    do: Error.fail(:invalid_document, ["path"], "Output selector path must be a list")

  defp encode_handler(%{kind: kind, target: target}, registry, reference)
       when kind in [:action, :flow, :transform] do
    with {:ok, target} <- reference.(target, registry, kind),
         do: {:ok, %{"kind" => Atom.to_string(kind), "target" => target}}
  end

  defp encode_handler(%{kind: :forward, target: %{kind: :parent}}, _registry, _reference),
    do: {:ok, %{"kind" => "forward", "target" => %{"kind" => "parent"}}}

  defp encode_handler(
         %{kind: :forward, target: %{kind: :agent, name: name}},
         registry,
         _reference
       ) do
    with {:ok, name} <- Value.encode(name, registry),
         do: {:ok, %{"kind" => "forward", "target" => %{"kind" => "agent", "name" => name}}}
  end

  defp encode_handler(_handler, _registry, _reference),
    do: Error.fail(:invalid_handler, [], "Agent definition contains an invalid route handler")

  defp decode_handler(%{"kind" => kind, "target" => target} = handler, registry)
       when map_size(handler) == 2 and kind in ["action", "flow", "transform"] do
    kind = String.to_existing_atom(kind)

    with {:ok, target} <- at(Registry.decode_reference(registry, target, kind), ["target"]),
         do: {:ok, %{kind: kind, target: target}}
  end

  defp decode_handler(
         %{"kind" => "forward", "target" => %{"kind" => "parent"} = target} = handler,
         _registry
       )
       when map_size(handler) == 2 and map_size(target) == 1,
       do: {:ok, %{kind: :forward, target: %{kind: :parent}}}

  defp decode_handler(
         %{"kind" => "forward", "target" => %{"kind" => "agent", "name" => name} = target} =
           handler,
         registry
       )
       when map_size(handler) == 2 and map_size(target) == 2 do
    with {:ok, name} <- at(Value.decode(name, registry), ["target", "name"]),
         do: {:ok, %{kind: :forward, target: %{kind: :agent, name: name}}}
  end

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
    decode_map(topology,
      agents: &decode_list(&1, fn member -> decode_member(member, registry) end),
      connections: &decode_list(&1, fn connection -> decode_connection(connection, registry) end)
    )
  end

  defp encode_member(member, registry) do
    fields = [
      name: &Value.encode(&1, registry),
      definition: &encode_nested_definition(&1, registry),
      count: &Value.encode(&1, registry),
      initial_state: &Value.encode(&1, registry)
    ]

    fields =
      if Map.has_key?(member, :identities),
        do: fields ++ [identities: &Value.encode(&1, registry)],
        else: fields

    encode_map(member, fields)
  end

  defp decode_member(member, registry) do
    fields = [
      name: &Value.decode(&1, registry),
      definition: &decode_nested_definition(&1, registry),
      count: &Value.decode(&1, registry),
      initial_state: &Value.decode(&1, registry)
    ]

    fields =
      if is_map(member) and Map.has_key?(member, "identities"),
        do: fields ++ [identities: &Value.decode(&1, registry)],
        else: fields

    decode_map(member, fields)
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
    encode_map(connection,
      from: &Value.encode(&1, registry),
      to: &Value.encode(&1, registry),
      path: nil,
      delivery: &{:ok, Atom.to_string(&1)}
    )
  end

  defp decode_connection(connection, registry) do
    decode_map(connection,
      from: &Value.decode(&1, registry),
      to: &Value.decode(&1, registry),
      delivery: &delivery/1,
      path: nil
    )
  end

  defp delivery("single"), do: {:ok, :single}
  defp delivery("broadcast"), do: {:ok, :broadcast}
  defp delivery(_value), do: Error.fail(:invalid_document, [], "Invalid Agent delivery value")

  defp encode_extension(extension, registry) do
    encode_map(extension,
      provider: &encode_reference(&1, registry, [:extension, :plugin]),
      data: &Extension.encode_authoring_data(extension.provider, &1, registry),
      id: nil,
      vsn: nil
    )
  end

  defp encode_map(value, fields), do: map_fields(value, fields, :encode)

  defp decode_map(value, fields, optional \\ []) do
    names = Enum.map(Keyword.keys(fields), &Atom.to_string/1)
    optional = Enum.map(optional, &Atom.to_string/1)

    with :ok <- object(value, names -- optional, optional),
         do: map_fields(value, fields, :decode)
  end

  defp map_fields(value, fields, direction) do
    with {:ok, entries} <-
           Authoring.traverse(fields, fn {key, transform} ->
             name = Atom.to_string(key)
             input = Map.get(value, if(direction == :encode, do: key, else: name))
             result = if transform, do: transform.(input), else: {:ok, input}
             result = if direction == :decode, do: at(result, [name]), else: result

             with {:ok, output} <- result,
                  do: {:ok, {if(direction == :encode, do: name, else: key), output}}
           end),
         do: {:ok, Map.new(entries)}
  end

  defp decode_extension(extension, registry) do
    with {:ok, extension} <-
           decode_map(extension,
             provider: &Registry.decode_reference(registry, &1, [:extension, :plugin]),
             data: nil,
             id: nil,
             vsn: nil
           ),
         {:ok, data} <-
           at(
             Extension.decode_authoring_data(extension.provider, extension.data, registry),
             ["data"]
           ) do
      {:ok, %{extension | data: data}}
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

  defp object(value, required, optional \\ [])

  defp object(value, required, optional) when is_map(value) and not is_struct(value) do
    keys = Map.keys(value)

    if required -- keys == [] and keys -- (required ++ optional) == [],
      do: :ok,
      else: Error.fail(:invalid_document, [], "Unknown or missing Agent document fields")
  end

  defp object(_value, _required, _optional),
    do: Error.fail(:invalid_document, [], "Agent document object must be a map")

  defp document_version(%{"type" => "jido.agent.definition", "vsn" => 1}), do: :ok

  defp document_version(%{"vsn" => version}) do
    Error.fail(
      :unsupported_document,
      ["vsn"],
      "Agent definition document version is not supported",
      %{vsn: version, supported_vsns: [1]}
    )
  end

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

  defp authoring_issue(error) do
    fields = if is_map(error), do: error, else: %{}
    details = if is_map(Map.get(fields, :details)), do: fields.details, else: %{}

    message =
      if Map.get(fields, :__exception__),
        do: Exception.message(error),
        else: inspect(error)

    Issue.new(
      Map.get(fields, :code) || :invalid_document,
      Enum.map(Map.get(fields, :path, []), &json_path_segment/1),
      message,
      details: details
    )
  end

  defp at({:error, error}, path) do
    issue = authoring_issue(error)
    {:error, %{issue | path: path ++ issue.path}}
  end

  defp at(result, _path), do: result

  defp json_path_segment(segment) when is_atom(segment), do: Atom.to_string(segment)
  defp json_path_segment(segment), do: segment
end
