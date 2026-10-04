defmodule Jido.Topology.Codec do
  @moduledoc """
  Serializes static topology definitions to versioned JSON-compatible documents.

  Version 2 embeds included definitions, import bindings, and exports. Source
  modules for included topologies are resolved during construction; stored
  composition is a snapshot of their definitions. Version 3 adds neutral
  Agent definitions and separate runtime children, directors, and gates.
  Version 2 documents cannot contain the new fields.

  This Codec uses `Jido.Codec.Registry` for Agent modules, data schemas,
  atoms, and static values. Stored strings cannot create atoms or modules.
  `encode/1` derives a temporary Registry. Supply stable Registry IDs to
  `encode/2` for database storage. Instance input, plans, PIDs, Agent state,
  and runtime status are not part of the document.

  `decode/3` also accepts explicit instance options. Document limits are shared
  with the Agent Codec: depth 100, 100000 nodes, 10000 collection entries, and
  1 MiB per string. The authoring format has no database dependency.
  """
  alias Jido.Agent.Authoring
  alias Jido.Codec.{Data, Registry}
  alias Jido.Topology
  alias Jido.Topology.EntryMetadata
  alias Jido.Topology.Codec.{Deriver, Value}

  @collections EntryMetadata.collections()
  @fields ~w(type version name schema metadata agents groups resources relationships connections startup includes imports exports children)
  @value_fields [
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
    :depends_on,
    :node,
    :gate,
    :input
  ]

  @type document :: %{required(String.t()) => term()}

  @doc "Encodes a definition and derives a temporary Registry."
  @spec encode(Topology.t()) ::
          {:ok, document(), Registry.t()} | {:error, term()}
  def encode(definition) do
    with {:ok, definition} <- Topology.new(definition),
         {:ok, registry} <- Deriver.topology(definition),
         {:ok, document} <- encode_validated(definition, registry),
         :ok <- Data.check_document(document),
         do: {:ok, document, registry}
  end

  @doc "Encodes a definition through a trusted Registry."
  @spec encode(Topology.t(), Registry.t() | map()) ::
          {:ok, document()} | {:error, term()}
  def encode(definition, registry) do
    with {:ok, definition} <- Topology.new(definition),
         {:ok, registry} <- Registry.new(registry),
         {:ok, document} <- encode_validated(definition, registry),
         :ok <- Data.check_document(document),
         do: {:ok, document}
  end

  defp encode_validated(definition, registry) do
    with {:ok, schema} <- Registry.identifier(registry, :schema, definition.schema),
         {:ok, metadata} <- Value.encode(definition.metadata, registry),
         {:ok, collections} <-
           Authoring.traverse(collections(version(definition)), fn {_kind, collection} ->
             with {:ok, entries} <-
                    Authoring.traverse(
                      Map.fetch!(definition, collection),
                      &encode_entry(&1, registry)
                    ),
                  do: {:ok, {Atom.to_string(collection), entries}}
           end),
         {:ok, startup} <- encode_entry(definition.startup, registry) do
      document =
        Map.merge(Map.new(collections), %{
          "type" => "jido.topology",
          "version" => version(definition),
          "name" => definition.name,
          "schema" => schema,
          "metadata" => metadata,
          "startup" => startup
        })

      {:ok, document}
    end
  end

  @doc "Decodes a definition without starting processes."
  @spec decode(document(), Registry.t() | map()) ::
          {:ok, Topology.t()} | {:error, term()}
  def decode(document, registry) do
    with :ok <- Data.check_document(document),
         {:ok, registry} <- Registry.new(registry),
         {:ok, attrs} <- decode_document(document, registry),
         do: Topology.new(attrs)
  end

  defp decode_document(document, registry) do
    with :ok <- document_header(document),
         {:ok, schema} <- Registry.resolve(registry, document["schema"], :schema),
         {:ok, metadata} <- Value.decode(document["metadata"], registry),
         {:ok, collections} <-
           Authoring.traverse(@collections, fn {kind, collection} ->
             with {:ok, entries} <-
                    Authoring.traverse(
                      Map.get(document, Atom.to_string(collection), []),
                      &decode_entry(&1, entry_fields(kind, document["version"]), registry)
                    ),
                  do: {:ok, {collection, entries}}
           end),
         {:ok, startup} <-
           decode_entry(document["startup"], EntryMetadata.fields(:startup), registry) do
      {:ok,
       Map.merge(Map.new(collections), %{
         name: document["name"],
         schema: schema,
         metadata: metadata,
         startup: startup
       })}
    end
  end

  @doc "Decodes a definition and constructs an instance with explicit input."
  @spec decode(document(), Registry.t() | map(), map() | keyword()) ::
          {:ok, Jido.Topology.Instance.t()} | {:error, term()}
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

  defp document_header(%{"type" => "jido.topology", "version" => version} = document)
       when version in [2, 3],
       do:
         Data.object(
           document,
           if(version == 2, do: List.delete(@fields, "children"), else: @fields)
         )

  defp document_header(_), do: Authoring.error("Unknown topology document type or version")

  defp encode_field(:topology, value, registry), do: encode_validated(value, registry)

  defp encode_field(:bindings, values, registry),
    do: Authoring.traverse(values, &encode_entry(&1, registry))

  defp encode_field(:kind, value, _), do: {:ok, Atom.to_string(value)}
  defp encode_field(:definition, value, registry), do: Jido.Agent.Codec.encode(value, registry)
  defp encode_field(:director, nil, _), do: {:ok, nil}
  defp encode_field(:director, value, registry), do: Jido.Agent.Codec.encode(value, registry)
  defp encode_field(:activation, value, _), do: {:ok, Atom.to_string(value)}
  defp encode_field(:module, value, registry), do: Registry.identifier(registry, :agent, value)

  defp encode_field(:on_parent_exit, value, _),
    do: {:ok, Atom.to_string(value)}

  defp encode_field(field, value, registry)
       when field in @value_fields,
       do: Value.encode(value, registry)

  defp encode_field(_, value, _), do: {:ok, value}

  defp decode_field(:topology, value, registry), do: decode_document(value, registry)

  defp decode_field(:bindings, values, registry),
    do: Authoring.traverse(values, &decode_entry(&1, EntryMetadata.fields(:binding), registry))

  defp decode_field(:kind, "agent", _), do: {:ok, :agent}
  defp decode_field(:kind, "group", _), do: {:ok, :group}
  defp decode_field(:kind, "bus", _), do: {:ok, :bus}
  defp decode_field(:kind, _, _), do: Authoring.error("Unknown topology endpoint kind")
  defp decode_field(:module, value, registry), do: Registry.resolve(registry, value, :agent)
  defp decode_field(:definition, value, registry), do: Jido.Agent.Codec.decode(value, registry)
  defp decode_field(:director, nil, _), do: {:ok, nil}
  defp decode_field(:director, value, registry), do: Jido.Agent.Codec.decode(value, registry)
  defp decode_field(:activation, "eager", _), do: {:ok, :eager}
  defp decode_field(:activation, "deferred", _), do: {:ok, :deferred}
  defp decode_field(:activation, "lazy", _), do: {:ok, :lazy}
  defp decode_field(:activation, _, _), do: Authoring.error("Unknown topology activation mode")
  defp decode_field(:on_parent_exit, "stop", _), do: {:ok, :stop}
  defp decode_field(:on_parent_exit, "continue", _), do: {:ok, :continue}
  defp decode_field(:on_parent_exit, "emit_orphan", _), do: {:ok, :emit_orphan}

  defp decode_field(:on_parent_exit, _, _),
    do: Authoring.error("Unknown topology policy")

  defp decode_field(field, value, registry)
       when field in @value_fields,
       do: Value.decode(value, registry)

  defp decode_field(_, value, _), do: {:ok, value}

  defp version(definition) do
    if definition.children != [] or
         Enum.any?(definition.agents ++ definition.groups, &Map.has_key?(&1, :definition)) or
         Enum.any?(definition.includes, &(version(&1.topology) == 3)), do: 3, else: 2
  end

  defp collections(2), do: Enum.reject(@collections, &(elem(&1, 1) == :children))
  defp collections(3), do: @collections
  defp entry_fields(kind, 2), do: List.delete(EntryMetadata.fields(kind), :definition)
  defp entry_fields(kind, 3), do: EntryMetadata.fields(kind)
end
