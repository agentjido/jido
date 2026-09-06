defmodule Jido.Agent.Codec do
  @moduledoc """
  Encodes Agent authoring data as a versioned JSON-compatible document.

  The document contains static configuration only. `decode/2` returns a neutral
  definition; `decode/3` constructs a complete Agent with explicit instance
  options. Executable code and schemas are resolved through a trusted Registry.
  The codec never derives module names or creates atoms from document strings.

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
  """
  alias Jido.Agent
  alias Jido.Agent.Authoring
  alias Jido.Agent.Codec.{Data, Registry}

  @fields ~w(type version module name description schema metadata plugins routes)

  @doc "Encodes authoring data with a generated temporary Registry."
  def encode(agent) do
    with {:ok, agent} <- Agent.validate(agent),
         {:ok, registry} <- Jido.Agent.Codec.Deriver.agent(agent),
         {:ok, document} <- encode_generated(agent, registry),
         do: {:ok, document, registry}
  end

  @doc "Encodes authoring data through a trusted Registry."
  def encode(agent, registry) do
    with {:ok, agent} <- Agent.validate(agent), do: encode_validated(agent, registry)
  end

  defp encode_generated(%Agent{id: nil, state: nil} = agent, registry),
    do: encode_validated(agent, registry)

  # Keep instance state parsing: static schema transforms need not be idempotent.
  defp encode_generated(agent, registry), do: encode(agent, registry)

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
        "version" => 1,
        "module" => module,
        "name" => agent.name,
        "description" => agent.description,
        "schema" => schema,
        "metadata" => metadata,
        "plugins" => plugins,
        "routes" => routes
      }

      document =
        if is_nil(agent.max_state_size),
          do: document,
          else: Map.put(document, "max_state_size", agent.max_state_size)

      with :ok <- Data.check_document(document), do: {:ok, document}
    end
  end

  @doc "Decodes one neutral Agent definition."
  def decode(document, registry) do
    with :ok <- Data.check_document(document),
         :ok <- definition_object(document),
         :ok <- version(document, "jido.agent"),
         {:ok, registry} <- Registry.new(registry),
         {:ok, module} <- Registry.resolve(registry, document["module"], :agent),
         {:ok, schema} <- Registry.resolve(registry, document["schema"], :schema),
         {:ok, metadata} <- Data.decode(document["metadata"], registry),
         {:ok, plugins} <-
           collection(document["plugins"], &Jido.Plugin.Codec.decode(&1, registry)),
         {:ok, routes} <- collection(document["routes"], &decode_route(&1, registry)) do
      Agent.new(%{
        module: module,
        name: document["name"],
        description: document["description"],
        max_state_size: document["max_state_size"],
        schema: schema,
        metadata: metadata,
        plugins: plugins,
        routes: routes
      })
    end
  end

  @doc "Decodes a complete Agent with caller-supplied instance options."
  def decode(document, registry, opts) do
    with {:ok, definition} <- decode(document, registry), do: Agent.instantiate(definition, opts)
  end

  defp definition_object(document) when is_map(document) and not is_struct(document),
    do: object(Map.delete(document, "max_state_size"), @fields)

  defp definition_object(document), do: object(document, @fields)

  defp encode_route(route, registry) do
    {target, defaults} = target(route.target)

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
         {:ok, match} <- resolve_match(data["match"], registry) do
      opts = [match: match, priority: data["priority"]]
      opts = if is_nil(defaults), do: opts, else: Keyword.put(opts, :defaults, defaults)
      Authoring.route(data["path"], target, opts)
    end
  end

  @doc false
  def target({target, defaults}) when is_map(defaults), do: {target, defaults}
  def target(target), do: {target, nil}
  defp match_id(nil, _registry), do: {:ok, nil}
  defp match_id(match, registry), do: Registry.identifier(registry, :route_match, match)
  defp resolve_match(nil, _registry), do: {:ok, nil}
  defp resolve_match(id, registry), do: Registry.resolve(registry, id, :route_match)
  defp kind("action"), do: {:ok, :action}
  defp kind("flow"), do: {:ok, :flow}
  defp kind(_kind), do: Authoring.error("Unknown executable kind")

  @doc false
  def object(value, fields) when is_map(value) and not is_struct(value) do
    if Enum.sort(Map.keys(value)) == Enum.sort(fields),
      do: :ok,
      else: Authoring.error("Unknown or missing document fields")
  end

  def object(_value, _fields), do: Authoring.error("Document object must be a map")
  @doc false
  def version(%{"version" => 1, "type" => type}, type), do: :ok
  def version(_document, _type), do: Authoring.error("Unknown authoring document type or version")
  defp collection(value, fun) when is_list(value), do: Authoring.traverse(value, fun)
  defp collection(_value, _fun), do: Authoring.error("Document collection must be a list")
end
