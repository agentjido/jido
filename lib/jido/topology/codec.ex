defmodule Jido.Topology.Codec do
  @moduledoc """
  Serializes static topology definitions to versioned JSON-compatible documents.

  Version 2 embeds included definitions, import bindings, and exports. Version 1
  documents remain readable. Source modules for included topologies are resolved
  during construction; stored composition is a snapshot of their definitions.

  This Codec uses `Jido.Agent.Codec.Registry` for Agent modules, Zoi schemas,
  atoms, and static values. Stored strings cannot create atoms or modules.
  `encode/1` derives a temporary Registry. Supply stable Registry IDs to
  `encode/2` for database storage. Instance input, plans, PIDs, Agent state,
  and runtime status are not part of the document.

  `decode/3` also accepts explicit instance options. Document limits are shared
  with the Agent Codec: depth 100, 100000 nodes, 10000 collection entries, and
  1 MiB per string. The authoring format has no database dependency.
  """
  alias Jido.Agent.Authoring
  alias Jido.Agent.Codec, as: AgentCodec
  alias Jido.Agent.Codec.{Data, Registry}
  alias Jido.Topology
  alias Jido.Topology.Codec.Value

  @collections [
    :agents,
    :groups,
    :resources,
    :relationships,
    :connections,
    :includes,
    :imports,
    :exports
  ]
  @v1_fields ~w(type version name schema metadata agents groups resources relationships connections startup)
  @fields @v1_fields ++ ~w(includes imports exports)

  @doc "Encodes a definition and derives a temporary Registry."
  def encode(definition) do
    with {:ok, definition} <- Topology.new(definition),
         {:ok, registry} <- Value.registry(definition),
         {:ok, document} <- encode_validated(definition, registry),
         do: {:ok, document, registry}
  end

  @doc "Encodes a definition through a trusted Registry."
  def encode(definition, registry) do
    with {:ok, definition} <- Topology.new(definition),
         {:ok, registry} <- Registry.new(registry),
         do: encode_validated(definition, registry)
  end

  defp encode_validated(definition, registry) do
    with {:ok, schema} <- Registry.identifier(registry, :schema, definition.schema),
         {:ok, metadata} <- Value.encode(definition.metadata, registry),
         {:ok, collections} <-
           Authoring.traverse(@collections, fn kind ->
             with {:ok, entries} <-
                    Authoring.traverse(Map.fetch!(definition, kind), &encode_entry(&1, registry)),
                  do: {:ok, {Atom.to_string(kind), entries}}
           end),
         {:ok, startup} <- encode_entry(definition.startup, registry) do
      document =
        Map.merge(Map.new(collections), %{
          "type" => "jido.topology",
          "version" => 2,
          "name" => definition.name,
          "schema" => schema,
          "metadata" => metadata,
          "startup" => startup
        })

      with :ok <- Data.check_document(document), do: {:ok, document}
    end
  end

  @doc "Decodes a definition without starting processes."
  def decode(document, registry) do
    with :ok <- Data.check_document(document),
         :ok <- document_header(document),
         {:ok, registry} <- Registry.new(registry),
         {:ok, schema} <- Registry.resolve(registry, document["schema"], :schema),
         {:ok, metadata} <- Value.decode(document["metadata"], registry),
         {:ok, collections} <-
           Authoring.traverse(@collections, fn kind ->
             with {:ok, entries} <-
                    Authoring.traverse(
                      Map.get(document, Atom.to_string(kind), []),
                      &decode_entry(&1, fields(kind), registry)
                    ),
                  do: {:ok, {kind, entries}}
           end),
         {:ok, startup} <- decode_entry(document["startup"], fields(:startup), registry) do
      Topology.new(
        Map.merge(Map.new(collections), %{
          name: document["name"],
          schema: schema,
          metadata: metadata,
          startup: startup
        })
      )
    end
  end

  @doc "Decodes a definition and constructs an instance with explicit input."
  def decode(document, registry, opts) do
    with {:ok, definition} <- decode(document, registry),
         do: Topology.instantiate(definition, opts)
  end

  defp encode_entry(entry, registry) do
    with {:ok, pairs} <-
           Authoring.traverse(Enum.sort(entry), fn {key, value} ->
             with {:ok, value} <- encode_field(key, value, registry),
                  do: {:ok, {Atom.to_string(key), value}}
           end),
         do: {:ok, Map.new(pairs)}
  end

  defp decode_entry(entry, fields, registry) when is_map(entry) and not is_struct(entry) do
    mapping = Map.new(fields, &{Atom.to_string(&1), &1})

    with :ok <- Authoring.keys(entry, Map.keys(mapping)),
         {:ok, pairs} <-
           Authoring.traverse(Enum.sort(entry), fn {key, value} ->
             field = Map.fetch!(mapping, key)
             with {:ok, value} <- decode_field(field, value, registry), do: {:ok, {field, value}}
           end),
         do: {:ok, Map.new(pairs)}
  end

  defp decode_entry(_, _, _), do: Authoring.error("Expected a topology record")

  defp fields(:agents), do: [:key, :module, :initial_state, :depends_on]
  defp fields(:groups), do: fields(:agents) ++ [:count, :members, :key_by]
  defp fields(:resources), do: [:key, :config]
  defp fields(:relationships), do: [:parent, :child, :on_parent_exit]
  defp fields(:connections), do: [:agent, :to, :path]
  defp fields(:startup), do: [:concurrency, :ready, :max_agents, :retry_interval, :task_timeout]
  defp fields(:includes), do: [:key, :topology, :inputs, :bindings]
  defp fields(:imports), do: [:key, :kind]
  defp fields(:exports), do: [:key, :kind, :from]

  defp document_header(%{"type" => "jido.topology", "version" => 1} = document),
    do: AgentCodec.object(document, @v1_fields)

  defp document_header(%{"type" => "jido.topology", "version" => 2} = document),
    do: AgentCodec.object(document, @fields)

  defp document_header(_), do: Authoring.error("Unknown topology document type or version")

  defp encode_field(:topology, value, registry), do: encode(value, registry)

  defp encode_field(:bindings, values, registry),
    do: Authoring.traverse(values, &encode_entry(&1, registry))

  defp encode_field(:kind, value, _), do: {:ok, Atom.to_string(value)}
  defp encode_field(:module, value, registry), do: Registry.identifier(registry, :agent, value)

  defp encode_field(field, value, _) when field in [:ready, :on_parent_exit],
    do: {:ok, Atom.to_string(value)}

  defp encode_field(field, value, registry)
       when field in [
              :initial_state,
              :config,
              :count,
              :members,
              :key_by,
              :inputs,
              :from,
              :to,
              :parent,
              :child,
              :agent,
              :depends_on
            ],
       do: Value.encode(value, registry)

  defp encode_field(_, value, _), do: {:ok, value}

  defp decode_field(:topology, value, registry), do: decode(value, registry)

  defp decode_field(:bindings, values, registry),
    do: Authoring.traverse(values, &decode_entry(&1, [:key, :to], registry))

  defp decode_field(:kind, "agent", _), do: {:ok, :agent}
  defp decode_field(:kind, "group", _), do: {:ok, :group}
  defp decode_field(:kind, "bus", _), do: {:ok, :bus}
  defp decode_field(:kind, _, _), do: Authoring.error("Unknown topology endpoint kind")
  defp decode_field(:module, value, registry), do: Registry.resolve(registry, value, :agent)
  defp decode_field(:ready, "all", _), do: {:ok, :all}
  defp decode_field(:on_parent_exit, "stop", _), do: {:ok, :stop}
  defp decode_field(:on_parent_exit, "continue", _), do: {:ok, :continue}
  defp decode_field(:on_parent_exit, "emit_orphan", _), do: {:ok, :emit_orphan}

  defp decode_field(field, _, _) when field in [:ready, :on_parent_exit],
    do: Authoring.error("Unknown topology policy")

  defp decode_field(field, value, registry)
       when field in [
              :initial_state,
              :config,
              :count,
              :members,
              :key_by,
              :inputs,
              :from,
              :to,
              :parent,
              :child,
              :agent,
              :depends_on
            ],
       do: Value.decode(value, registry)

  defp decode_field(_, value, _), do: {:ok, value}
end
