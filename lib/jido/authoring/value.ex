defmodule Jido.Authoring.Value do
  @moduledoc """
  Encodes and decodes portable values used inside authoring documents.

  The format supports JSON scalar values, proper lists, plain maps, and atoms
  that a trusted `Jido.Authoring.Registry` identifies. Map keys can be valid
  UTF-8 strings, non-negative integers, Booleans, or registered atoms.

  The format rejects structs, tuples, processes, invalid UTF-8 strings,
  improper lists, and collections or nesting above the documented limits.
  A document owner must also call `Jido.Authoring.Document.check/1` on the
  complete document to enforce its total node limit.
  """

  alias Jido.Authoring.Registry
  require Jido.Authoring.Limits

  @maximum_depth Jido.Authoring.Limits.maximum_depth()
  @maximum_collection_size Jido.Authoring.Limits.maximum_collection_size()

  defmodule Error do
    @moduledoc "An invalid portable authoring value."
    use Splode.Error,
      class: :invalid,
      fields: [message: "Invalid portable authoring value", reason: nil, details: %{}]

    @type reason ::
            :atom
            | :collection
            | :depth
            | :duplicate_key
            | :list
            | :map_entry
            | :map_key
            | :string
            | :tag
            | :value
    @type t :: %__MODULE__{
            message: String.t(),
            reason: reason(),
            path: list(),
            details: map()
          }
  end

  @doc "Encodes one portable value with registered atom identifiers."
  @spec encode(term(), Registry.t()) :: {:ok, term()} | {:error, Exception.t()}
  def encode(value, %Registry{} = registry), do: encode(value, registry, 0, [])

  @doc "Decodes one portable value through a trusted Registry."
  @spec decode(term(), Registry.t()) :: {:ok, term()} | {:error, Exception.t()}
  def decode(value, %Registry{} = registry), do: decode(value, registry, 0, [])

  defp encode(_value, _registry, depth, path) when depth > @maximum_depth,
    do: depth_error(path, depth)

  defp encode(value, _registry, _depth, _path)
       when is_nil(value) or is_boolean(value) or is_number(value),
       do: {:ok, value}

  defp encode(value, _registry, _depth, path) when is_binary(value),
    do: portable_string(value, path)

  defp encode(value, registry, _depth, path) when is_atom(value) do
    case Registry.reference(registry, :atom, value) do
      {:ok, {id, vsn}} ->
        {:ok, %{"$type" => "atom", "id" => id, "vsn" => vsn}}

      {:error, %Registry.Error{} = exception} ->
        prefix_registry_error({:error, exception}, path)
    end
  end

  defp encode(value, registry, depth, path) when is_list(value),
    do: map_list(value, registry, depth, path, &encode/4)

  defp encode(value, registry, depth, path) when is_map(value) and not is_struct(value) do
    with :ok <- collection_size(map_size(value), path),
         :ok <- validate_keys(value, path) do
      value
      |> encode_map_keys(registry, depth, path)
      |> encode_map_values(registry, depth, path)
      |> case do
        {:ok, entries} ->
          {:ok, %{"$type" => "map", "entries" => Enum.reverse(entries)}}

        error ->
          error
      end
    end
  end

  defp encode(_value, _registry, _depth, path),
    do: error(:value, "authoring data contains an unsupported value", path)

  defp decode(_value, _registry, depth, path) when depth > @maximum_depth,
    do: depth_error(path, depth)

  defp decode(value, _registry, _depth, _path)
       when is_nil(value) or is_boolean(value) or is_number(value),
       do: {:ok, value}

  defp decode(value, _registry, _depth, path) when is_binary(value),
    do: portable_string(value, path)

  defp decode(values, registry, depth, path) when is_list(values),
    do: map_list(values, registry, depth, path, &decode/4)

  defp decode(%{"$type" => "atom", "id" => id, "vsn" => vsn} = value, registry, _depth, path)
       when map_size(value) == 3 do
    case Registry.resolve(registry, {id, vsn}, :atom) do
      {:ok, atom} when is_atom(atom) -> {:ok, atom}
      {:ok, _value} -> error(:atom, "authoring atom reference must resolve to an atom", path)
      {:error, %Registry.Error{} = exception} -> prefix_registry_error({:error, exception}, path)
    end
  end

  defp decode(%{"$type" => "map", "entries" => entries} = value, registry, depth, path)
       when map_size(value) == 2 and is_list(entries) do
    cond do
      List.improper?(entries) ->
        error(:list, "authoring value must contain proper lists", path ++ ["entries"])

      length(entries) > @maximum_collection_size ->
        collection_error(path, length(entries))

      true ->
        entries
        |> Enum.with_index()
        |> Enum.reduce_while({:ok, []}, fn
          {%{"key" => key, "value" => item} = entry, index}, {:ok, pairs}
          when map_size(entry) == 2 ->
            entry_path = path ++ ["entries", index]

            with {:ok, key} <- decode(key, registry, depth + 1, entry_path ++ ["key"]),
                 :ok <- validate_key(key, entry_path ++ ["key"]),
                 {:ok, item} <- decode(item, registry, depth + 1, entry_path ++ ["value"]) do
              {:cont, {:ok, [{key, item} | pairs]}}
            else
              {:error, exception} -> {:halt, {:error, exception}}
            end

          {_entry, index}, _acc ->
            {:halt,
             error(
               :map_entry,
               "authoring map entry must contain a key and value",
               path ++ ["entries", index]
             )}
        end)
        |> case do
          {:ok, pairs} ->
            decoded = Map.new(pairs)

            cond do
              length(pairs) != map_size(decoded) ->
                error(:duplicate_key, "authoring map contains a duplicate key", path)

              is_struct(decoded) ->
                error(:value, "authoring data contains an unsupported value", path)

              true ->
                {:ok, decoded}
            end

          error ->
            error
        end
    end
  end

  defp decode(_value, _registry, _depth, path),
    do: error(:tag, "authoring data contains an invalid tagged value", path)

  @doc false
  @spec encoded_key_sort_key(term()) :: {non_neg_integer(), term()}
  def encoded_key_sort_key(key) when is_integer(key), do: {0, key}
  def encoded_key_sort_key(key) when is_binary(key), do: {1, key}

  def encoded_key_sort_key(%{"$type" => "atom", "id" => id, "vsn" => vsn})
      when is_binary(id) and is_integer(vsn),
      do: {2, {id, vsn}}

  def encoded_key_sort_key(key) when is_boolean(key), do: {3, key}

  defp encode_map_keys(value, registry, depth, path) do
    Enum.reduce_while(value, {:ok, []}, fn {key, item}, {:ok, entries} ->
      case encode(key, registry, depth + 1, path ++ [key]) do
        {:ok, encoded_key} -> {:cont, {:ok, [{encoded_key, key, item} | entries]}}
        {:error, exception} -> {:halt, {:error, exception}}
      end
    end)
  end

  defp encode_map_values({:ok, entries}, registry, depth, path) do
    entries
    |> Enum.sort_by(fn {encoded_key, _key, _item} -> encoded_key_sort_key(encoded_key) end)
    |> Enum.reduce_while({:ok, []}, fn {encoded_key, key, item}, {:ok, result} ->
      case encode(item, registry, depth + 1, path ++ [key]) do
        {:ok, encoded_item} ->
          entry = %{"key" => encoded_key, "value" => encoded_item}
          {:cont, {:ok, [entry | result]}}

        {:error, exception} ->
          {:halt, {:error, exception}}
      end
    end)
  end

  defp encode_map_values({:error, _exception} = error, _registry, _depth, _path), do: error

  defp map_list(values, registry, depth, path, mapper) do
    cond do
      List.improper?(values) ->
        error(:list, "authoring value must contain proper lists", path)

      length(values) > @maximum_collection_size ->
        collection_error(path, length(values))

      true ->
        values
        |> Enum.with_index()
        |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, mapped} ->
          case mapper.(item, registry, depth + 1, path ++ [index]) do
            {:ok, item} -> {:cont, {:ok, [item | mapped]}}
            {:error, exception} -> {:halt, {:error, exception}}
          end
        end)
        |> reverse_ok()
    end
  end

  defp collection_size(size, _path) when size <= @maximum_collection_size, do: :ok

  defp collection_size(size, path), do: collection_error(path, size)

  defp depth_error(path, actual),
    do:
      error(:depth, "authoring value exceeds its nesting limit", path, %{
        actual: actual,
        maximum_depth: @maximum_depth
      })

  defp collection_error(path, actual),
    do:
      error(:collection, "authoring value collection exceeds its size limit", path, %{
        actual: actual,
        maximum_size: @maximum_collection_size
      })

  defp portable_string(value, path) do
    if String.valid?(value),
      do: {:ok, value},
      else: error(:string, "authoring value strings must be valid UTF-8", path)
  end

  defp validate_key(key, _path)
       when is_binary(key) or (is_integer(key) and key >= 0) or
              (is_atom(key) and not is_nil(key)),
       do: :ok

  defp validate_key(_key, path),
    do: error(:map_key, "authoring data contains an unsupported map key", path)

  defp validate_keys(value, path) do
    if Enum.all?(Map.keys(value), &valid_key?/1),
      do: :ok,
      else: error(:map_key, "authoring data contains an unsupported map key", path)
  end

  defp valid_key?(key),
    do:
      is_binary(key) or (is_integer(key) and key >= 0) or
        (is_atom(key) and not is_nil(key))

  defp prefix_registry_error({:error, %Registry.Error{} = exception}, path),
    do: {:error, %{exception | details: Map.put(exception.details, :path, path)}}

  defp reverse_ok({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_ok(error), do: error

  defp error(reason, message, path, details \\ %{}),
    do: {:error, Error.exception(reason: reason, message: message, path: path, details: details)}
end
