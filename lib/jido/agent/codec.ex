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
  `Jido.Agent.Codec.Registry` with stable application IDs for stored documents.
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
  alias Jido.Agent.Codec.{Data, Registry}

  @fields_v1 ~w(type version module name description schema metadata plugins routes)
  @fields_v2 ~w(type version module vsn name description schema metadata plugins routes)

  @type document :: %{required(String.t()) => term()}

  @doc "Encodes authoring data with a generated temporary Registry."
  @spec encode(Agent.t()) ::
          {:ok, document(), Registry.t()} | {:error, term()}
  def encode(agent) do
    with {:ok, definition} <- neutral_definition(agent),
         {:ok, registry} <- Jido.Agent.Codec.Deriver.agent(definition),
         {:ok, document} <- encode_validated(definition, registry),
         do: {:ok, document, registry}
  end

  @doc "Encodes authoring data through a trusted Registry."
  @spec encode(Agent.t(), Registry.t() | map()) ::
          {:ok, document()} | {:error, term()}
  def encode(agent, registry) do
    with {:ok, definition} <- neutral_definition(agent),
         do: encode_validated(definition, registry)
  end

  defp encode_validated(agent, registry) do
    with {:ok, registry} <- Registry.new(registry),
         {:ok, module} <- Registry.identifier(registry, :agent, agent.module),
         {:ok, schema} <- Registry.identifier(registry, :schema, agent.schema),
         {:ok, metadata} <- Data.encode(agent.metadata, registry),
         {:ok, plugins} <-
           Authoring.traverse(agent.plugins, &Jido.Plugin.Codec.encode(&1, registry)),
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
          {:ok, Agent.t()} | {:error, term()}
  def decode(document, registry) do
    with :ok <- Data.check_document(document),
         {:ok, version} <- definition_object(document),
         {:ok, registry} <- Registry.new(registry),
         {:ok, module} <- Registry.resolve(registry, document["module"], :agent),
         vsn = document_vsn(document, version, module),
         {:ok, schema} <- Registry.resolve(registry, document["schema"], :schema),
         {:ok, metadata} <- Data.decode(document["metadata"], registry),
         {:ok, plugins} <-
           collection(document["plugins"], &Jido.Plugin.Codec.decode(&1, registry)),
         {:ok, routes} <- collection(document["routes"], &decode_route(&1, registry)) do
      Agent.new(%{
        module: module,
        vsn: vsn,
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
          {:ok, Agent.t()} | {:error, term()}
  def decode(document, registry, opts) do
    with {:ok, definition} <- decode(document, registry), do: Agent.instantiate(definition, opts)
  end

  defp definition_object(%{"type" => "jido.agent", "version" => 1} = document) do
    with :ok <- object(document, @fields_v1), do: {:ok, 1}
  end

  defp definition_object(%{"type" => "jido.agent", "version" => 2} = document) do
    with :ok <- object(document, @fields_v2), do: {:ok, 2}
  end

  defp definition_object(_document),
    do: Authoring.error("Unknown authoring document type or version")

  defp document_vsn(_document, 1, module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__agent_config__, 0) and
         function_exported?(module, :agent, 0),
       do: 1,
       else: nil
  end

  defp document_vsn(document, 2, _module), do: document["vsn"]

  defp neutral_definition(%Agent{} = agent) do
    cond do
      Agent.definition?(agent) -> Agent.validate_definition(agent)
      Agent.instance?(agent) -> agent |> Agent.definition() |> Agent.validate_definition()
      true -> Agent.validate(agent)
    end
  end

  defp neutral_definition(value), do: Agent.validate(value)

  defp encode_route(route, registry) do
    {target, defaults} = Authoring.split_target(route.target)

    with {:ok, executable} <- Jido.Executable.resolve(target),
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
    with :ok <- object(data, ~w(path target kind defaults match priority)),
         {:ok, kind} <- kind(data["kind"]),
         {:ok, target} <- Registry.resolve(registry, data["target"], kind),
         {:ok, defaults} <- Data.decode(data["defaults"], registry),
         {:ok, match} <- resolve_match(data["match"], registry),
         {:ok, target} <- decode_target(target, defaults) do
      Authoring.route(data["path"], target, match: match, priority: data["priority"])
    end
  end

  # Preserve tuple defaults, including structs, without relaxing the explicit
  # :defaults authoring option.
  defp decode_target(target, nil), do: {:ok, target}
  defp decode_target(target, defaults) when is_map(defaults), do: {:ok, {target, defaults}}

  defp decode_target(_target, _defaults),
    do: Authoring.error("Route defaults must be a plain map")

  defp match_id(nil, _registry), do: {:ok, nil}
  defp match_id(match, registry), do: Registry.identifier(registry, :route_match, match)
  defp resolve_match(nil, _registry), do: {:ok, nil}
  defp resolve_match(id, registry), do: Registry.resolve(registry, id, :route_match)
  defp kind("action"), do: {:ok, :action}
  defp kind("flow"), do: {:ok, :flow}
  defp kind(_kind), do: Authoring.error("Unknown executable kind")

  @doc false
  @spec object(term(), [String.t()]) :: :ok | {:error, term()}
  def object(value, fields) when is_map(value) and not is_struct(value) do
    if Enum.sort(Map.keys(value)) == Enum.sort(fields),
      do: :ok,
      else: Authoring.error("Unknown or missing document fields")
  end

  def object(_value, _fields), do: Authoring.error("Document object must be a map")
  @doc false
  @spec version(document(), String.t()) :: :ok | {:error, term()}
  def version(%{"version" => 1, "type" => type}, type), do: :ok
  def version(_document, _type), do: Authoring.error("Unknown authoring document type or version")
  defp collection(value, fun) when is_list(value), do: Authoring.traverse(value, fun)
  defp collection(_value, _fun), do: Authoring.error("Document collection must be a list")
end
