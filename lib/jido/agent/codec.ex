defmodule Jido.Agent.Codec do
  @moduledoc """
  Encodes Agent authoring data as a versioned JSON-compatible document.

  The document contains static configuration only. `decode/2` returns a neutral
  definition; `decode/3` constructs a complete Agent with explicit instance
  options. Executable code and schemas are resolved through a trusted Registry.
  The codec never derives module names or creates atoms from document strings.

  Encoding a definition or instance first derives and validates its neutral
  definition. Instance identity and live state are not parsed or encoded.

      {:ok, document, registry} = Jido.Agent.Codec.encode(agent)
      json = JSON.encode!(document)
      {:ok, restored} = Jido.Agent.Codec.decode(JSON.decode!(json), registry,
        id: agent.id, state: agent.state)

  Generated Registry IDs are for temporary transport and tests. Supply a
  `Jido.Codec.Registry` with stable application IDs for stored documents.
  This is authoring serialization, not an Agent checkpoint or effect journal.
  Documents are limited to 100 nested levels, 100000 nodes, 10000 entries per
  collection, and 1 MiB per string.

  Each route record stores caller-overridable input values in `"defaults"`.
  Valid direct definitions can contain local route-match closures. These
  runtime-only closures are outside the Codec subset. Encodable route matches
  must be external unary captures in the trusted Registry.
  """
  alias Jido.Agent
  alias Jido.Agent.Authoring
  alias Jido.Codec.{Data, Registry}

  @fields ~w(type version module vsn name description schema metadata plugins routes)

  @type document :: %{required(String.t()) => term()}

  @doc "Encodes authoring data with a generated temporary Registry."
  @spec encode(Agent.t()) ::
          {:ok, document(), Registry.t()} | {:error, term()}
  def encode(agent) do
    with {:ok, definition} <- neutral_definition(agent),
         {:ok, entries} <- registry_entries(definition),
         {:ok, registry} <- Registry.derive(entries),
         {:ok, document} <- encode_validated(definition, registry),
         do: {:ok, document, registry}
  end

  @doc "Encodes authoring data through a trusted Registry."
  @spec encode(Agent.t(), Registry.t() | map()) ::
          {:ok, document()} | {:error, term()}
  def encode(agent, registry) do
    with {:ok, definition} <- neutral_definition(agent),
         {:ok, registry} <- Registry.new(registry),
         do: encode_validated(definition, registry)
  end

  defp encode_validated(agent, registry) do
    with {:ok, module} <- Registry.identifier(registry, :agent, agent.module),
         {:ok, schema} <- Registry.identifier(registry, :schema, agent.schema),
         {:ok, metadata} <- Data.encode(agent.metadata, registry),
         {:ok, plugins} <-
           Authoring.traverse(agent.plugins, &Jido.Plugin.Codec.encode_declaration(&1, registry)),
         {:ok, routes} <- Authoring.traverse(agent.routes, &encode_route(&1, registry)) do
      document = %{
        "type" => "jido.agent",
        "version" => 2,
        "module" => module,
        "vsn" => agent.vsn,
        "name" => agent.name,
        "description" => agent.description,
        "schema" => schema,
        "metadata" => metadata,
        "plugins" => plugins,
        "routes" => routes
      }

      with :ok <- Data.check_document(document), do: {:ok, document}
    end
  end

  @doc "Decodes one neutral Agent definition."
  @spec decode(document(), Registry.t() | map()) ::
          {:ok, Agent.definition()} | {:error, term()}
  def decode(document, registry) do
    with {:ok, definition, _specs, _schema} <- decode_with_plugins(document, registry),
         do: {:ok, definition}
  end

  defp decode_with_plugins(document, registry) do
    with :ok <- Data.check_document(document),
         :ok <- definition_object(document),
         {:ok, registry} <- Registry.new(registry),
         {:ok, module} <- Registry.resolve(registry, document["module"], :agent),
         {:ok, schema} <- Registry.resolve(registry, document["schema"], :schema),
         {:ok, metadata} <- Data.decode(document["metadata"], registry),
         {:ok, plugins} <-
           collection(document["plugins"], &Jido.Plugin.Codec.decode_spec(&1, registry)),
         {:ok, routes} <- collection(document["routes"], &decode_route(&1, registry)) do
      Agent.Validation.new(%{
        module: module,
        vsn: document["vsn"],
        name: document["name"],
        description: document["description"],
        schema: schema,
        metadata: metadata,
        plugins: plugins,
        routes: routes
      })
    end
  end

  @doc "Decodes a complete Agent with caller-supplied instance options."
  @spec decode(document(), Registry.t() | map(), map() | keyword()) ::
          {:ok, Agent.instance()} | {:error, term()}
  def decode(document, registry, opts) do
    with {:ok, agent, _specs, _schema} <-
           Agent.Validation.instantiate_validated(decode_with_plugins(document, registry), opts),
         do: {:ok, agent}
  end

  defp definition_object(%{"type" => "jido.agent", "version" => 2} = document) do
    Data.object(document, @fields)
  end

  defp definition_object(_document),
    do: Authoring.error("Unknown authoring document type or version")

  defp neutral_definition(%Agent{id: nil, state: nil} = definition),
    do: Agent.validate_definition(definition)

  defp neutral_definition(%Agent{id: id, state: state} = agent)
       when is_binary(id) and byte_size(id) > 0 and is_map(state) and not is_struct(state),
       do: agent |> Agent.definition() |> Agent.validate_definition()

  defp neutral_definition(value), do: Agent.validate(value)

  @doc false
  def registry_entries(agent) do
    entries =
      [{:agent, agent.module}, {:schema, agent.schema}] ++
        Data.registry_entries(agent.metadata) ++
        Enum.flat_map(agent.plugins, &plugin_entries/1)

    with {:ok, routes} <- route_entries(agent.routes),
         do: {:ok, entries ++ routes}
  end

  defp plugin_entries({module, options}),
    do: [{:plugin, module} | Data.registry_entries(options)]

  defp route_entries(routes) do
    Authoring.traverse(routes, fn route ->
      {target, defaults} = Authoring.split_target(route.target)

      with {:ok, executable} <- Jido.Instruction.resolve(target) do
        entries = [{executable.kind, target} | Data.registry_entries(defaults)]

        {:ok,
         if(is_nil(route.match),
           do: entries,
           else: entries ++ [{:route_match, route.match}]
         )}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, List.flatten(entries)}
      error -> error
    end
  end

  defp encode_route(route, registry) do
    {target, defaults} = Authoring.split_target(route.target)

    with {:ok, executable} <- Jido.Instruction.resolve(target),
         {:ok, target_id} <- Registry.identifier(registry, executable.kind, target),
         {:ok, defaults} <- Data.encode(defaults, registry),
         {:ok, match} <- match_id(route.match, registry) do
      {:ok,
       %{
         "path" => route.path,
         "target" => target_id,
         "kind" => Atom.to_string(executable.kind),
         "defaults" => defaults,
         "match" => match,
         "priority" => route.priority
       }}
    end
  end

  defp decode_route(data, registry) do
    with :ok <- Data.object(data, ~w(path target kind defaults match priority)),
         {:ok, kind} <- kind(data["kind"]),
         {:ok, target} <- Registry.resolve(registry, data["target"], kind),
         {:ok, defaults} <- Data.decode(data["defaults"], registry),
         {:ok, match} <- resolve_match(data["match"], registry) do
      opts = if is_nil(defaults), do: [], else: [defaults: defaults]
      Authoring.route(data["path"], target, opts ++ [match: match, priority: data["priority"]])
    end
  end

  defp match_id(nil, _registry), do: {:ok, nil}
  defp match_id(match, registry), do: Registry.identifier(registry, :route_match, match)
  defp resolve_match(nil, _registry), do: {:ok, nil}
  defp resolve_match(id, registry), do: Registry.resolve(registry, id, :route_match)
  defp kind("action"), do: {:ok, :action}
  defp kind("flow"), do: {:ok, :flow}
  defp kind(_kind), do: Authoring.error("Unknown executable kind")

  defp collection(value, fun) when is_list(value), do: Authoring.traverse(value, fun)
  defp collection(_value, _fun), do: Authoring.error("Document collection must be a list")
end
