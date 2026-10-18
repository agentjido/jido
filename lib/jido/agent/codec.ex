defmodule Jido.Agent.Codec do
  @moduledoc """
  Versioned Agent documents with trusted references for schemas, code, and data atoms.

  Import never evaluates source or creates atoms. Providers use the same stored
  contribution Map as Elixir and DSL authoring. Import runs their normal validation.
  A JSON document is data; it does not start an Agent or restore an execution.
  """
  alias Jido.Agent
  alias Jido.Agent.{Authoring, Error}
  alias Jido.Codec.{Data, Registry}

  @fields ~w(id state module name description vsn schema metadata signal_source routes topology extensions)a
  @symbols ~w(path as defaults emits handler kind target agents connections name definition count initial_state from to delivery root agent single broadcast state key action flow transform pass_through id provider vsn data buses schedules timing every milliseconds cron expression timezone signal type)a
  @kinds [:agent, :action, :flow, :plugin, :extension, :transform, :schema, :atom, :value]

  @doc "Exports a document and a temporary Registry for local round trips."
  def encode(source) do
    with {:ok, agent} <- value(source),
         {:ok, registry} <- Registry.derive(references(agent)),
         {:ok, document} <- encode(agent, registry),
         do: {:ok, document, registry}
  end

  @doc "Exports a document with application-owned Registry identifiers."
  def encode(source, registry) do
    with {:ok, agent} <- value(source),
         {:ok, registry} <- Registry.new(registry),
         {:ok, fields} <- encode_fields(agent, registry),
         document = %{"type" => "jido.agent", "version" => 1, "agent" => fields},
         :ok <- Data.check_document(document),
         do: {:ok, document}
  end

  @doc "Imports a document through the trusted Registry and validates the complete value."
  def decode(document, registry) do
    with :ok <- Data.check_document(document),
         :ok <- Data.object(document, ~w(type version agent)),
         :ok <- version(document),
         {:ok, registry} <- Registry.new(registry),
         {:ok, fields} <- decode_fields(document["agent"], registry),
         do: build(fields)
  end

  def from_json(json, registry) when is_binary(json) and byte_size(json) <= 8_388_608 do
    case Jason.decode(json) do
      {:ok, document} -> decode(document, registry)
      {:error, _} -> Error.fail(:invalid_json, [], "Invalid Agent JSON")
    end
  end

  def from_json(_, _),
    do: Error.fail(:invalid_json, [], "Expected a JSON string of at most 8 MiB")

  defp version(%{"type" => "jido.agent", "version" => 1}), do: :ok
  defp version(_), do: Error.fail(:document_version, [], "Unknown Agent document type or version")

  defp value(%Agent{} = agent), do: Agent.validate(agent)
  defp value(map) when is_map(map), do: Agent.define(map)
  defp value(module), do: Jido.Agent.Validation.resolve(module)

  defp build(%{id: nil, state: nil} = fields), do: Agent.define(fields)

  defp build(fields) do
    with {:ok, definition} <- Agent.define(%{fields | id: nil, state: nil}),
         do: Agent.validate(%{definition | id: fields.id, state: fields.state})
  end

  defp encode_fields(agent, registry) do
    with {:ok, pairs} <-
           Authoring.traverse(@fields, fn key ->
             with {:ok, encoded} <- pack(Map.fetch!(agent, key), registry, 0),
                  do: {:ok, {Atom.to_string(key), encoded}}
           end),
         do: {:ok, Map.new(pairs)}
  end

  defp decode_fields(fields, registry) do
    with :ok <- Data.object(fields, Enum.map(@fields, &Atom.to_string/1)),
         {:ok, pairs} <-
           Authoring.traverse(@fields, fn key ->
             with {:ok, decoded} <- unpack(Map.fetch!(fields, Atom.to_string(key)), registry),
                  do: {:ok, {key, decoded}}
           end),
         do: {:ok, Map.new(pairs)}
  end

  defp pack(_, _, depth) when depth > 100,
    do: Error.fail(:document_depth, [], "Agent data is too deep")

  defp pack(value, _, _) when is_nil(value) or is_boolean(value) or is_number(value),
    do: {:ok, value}

  defp pack(value, registry, _) when is_binary(value), do: Data.encode(value, registry)

  defp pack(%Agent{} = agent, registry, _) do
    with {:ok, fields} <- encode_fields(agent, registry),
         do: {:ok, %{"$type" => "agent", "value" => fields}}
  end

  defp pack(value, registry, _) when is_struct(value),
    do: reference(value, registry, [:schema, :value])

  defp pack(value, _, _) when value in @symbols,
    do: {:ok, %{"$type" => "symbol", "name" => Atom.to_string(value)}}

  defp pack(value, registry, _) when is_atom(value),
    do: reference(value, registry, [:agent, :action, :flow, :extension, :plugin, :atom])

  defp pack(value, registry, depth) when is_map(value),
    do: Data.encode_map(value, &pack(&1, registry, depth + 1))

  defp pack(value, registry, depth) when is_list(value),
    do: Authoring.traverse(value, &pack(&1, registry, depth + 1))

  defp pack(value, registry, depth) when is_tuple(value) do
    case Registry.identifier(registry, :transform, value) do
      {:ok, _} ->
        reference(value, registry, [:transform])

      {:error, _} ->
        with {:ok, items} <-
               Authoring.traverse(Tuple.to_list(value), &pack(&1, registry, depth + 1)),
             do: {:ok, %{"$type" => "tuple", "items" => items}}
    end
  end

  defp pack(_, _, _),
    do: Error.fail(:runtime_value, [], "Agent JSON cannot contain runtime values")

  defp reference(value, registry, kinds) do
    Enum.reduce_while(
      kinds,
      Error.fail(:unknown_reference, [], "Registry has no identifier for Agent data"),
      fn kind, error ->
        case Registry.identifier(registry, kind, value) do
          {:ok, id} ->
            {:halt, {:ok, %{"$type" => "reference", "kind" => Atom.to_string(kind), "id" => id}}}

          _ ->
            {:cont, error}
        end
      end
    )
  end

  defp unpack(value, _)
       when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value),
       do: {:ok, value}

  defp unpack(value, registry) when is_list(value),
    do: Authoring.traverse(value, &unpack(&1, registry))

  defp unpack(%{"$type" => "symbol", "name" => name} = value, _) when map_size(value) == 2 do
    case Enum.find(@symbols, &(Atom.to_string(&1) == name)) do
      nil -> Error.fail(:unknown_symbol, [], "Unknown Agent document symbol")
      atom -> {:ok, atom}
    end
  end

  defp unpack(%{"$type" => "reference", "kind" => kind, "id" => id} = value, registry)
       when map_size(value) == 3 do
    case Enum.find(@kinds, &(Atom.to_string(&1) == kind)) do
      nil -> Error.fail(:unknown_reference_kind, [], "Unknown Registry reference kind")
      kind -> Registry.resolve(registry, id, kind)
    end
  end

  defp unpack(%{"$type" => "agent", "value" => fields} = value, registry)
       when map_size(value) == 2 do
    with {:ok, fields} <- decode_fields(fields, registry), do: build(fields)
  end

  defp unpack(%{"$type" => "map", "entries" => entries} = value, registry)
       when map_size(value) == 2 and is_list(entries),
       do: Data.decode_map(entries, &unpack(&1, registry), "Invalid Agent Map entry")

  defp unpack(%{"$type" => "tuple", "items" => items} = value, registry)
       when map_size(value) == 2 and is_list(items) do
    with {:ok, items} <- Authoring.traverse(items, &unpack(&1, registry)),
         do: {:ok, List.to_tuple(items)}
  end

  defp unpack(%{"$type" => "binary"} = value, registry), do: Data.decode(value, registry)
  defp unpack(_, _), do: Error.fail(:invalid_document, [], "Invalid Agent document value")

  defp references(%Agent{} = value),
    do: Enum.flat_map(@fields, &references(Map.fetch!(value, &1)))

  defp references(%Zoi.Types.Map{} = value), do: [{:schema, value}]
  defp references(value) when is_struct(value), do: [{:value, value}]
  defp references(value) when is_nil(value) or is_boolean(value) or value in @symbols, do: []

  defp references(value) when is_atom(value) do
    kind =
      cond do
        Code.ensure_loaded?(value) and function_exported?(value, :__jido_plugin__, 0) ->
          :plugin

        Code.ensure_loaded?(value) and function_exported?(value, :endpoint_kinds, 0) ->
          :extension

        Jido.Agent.Validation.loaded_agent_module?(value) ->
          :agent

        true ->
          case Jido.Instruction.resolve(value) do
            {:ok, %{kind: kind}} -> kind
            _ -> :atom
          end
      end

    [{kind, value}]
  end

  defp references(value) when is_map(value),
    do: Enum.flat_map(value, fn {k, v} -> references(k) ++ references(v) end)

  defp references(value) when is_tuple(value), do: references(Tuple.to_list(value))
  defp references(value) when is_list(value), do: Enum.flat_map(value, &references/1)
  defp references(_), do: []
end
