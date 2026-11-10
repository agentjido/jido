defmodule Jido.Codec.Document do
  @moduledoc """
  Parses JSON and enforces resource limits on one complete codec document.

  `check/1` limits nesting, collection size, and the total number of nodes.
  `check_json/2` also checks JSON compatibility and the encoded byte size.
  `decode_json/2` rejects duplicate keys, copies retained strings, and applies
  the same resource limits while it converts ordered JSON objects to maps.
  These functions do not validate the document owner's fields or portable
  values.
  """

  @maximum_depth 100
  @maximum_collection_size 10_000
  @maximum_document_nodes 100_000
  defmodule Error do
    @moduledoc "A codec document that exceeds a resource or shape limit."
    use Splode.Error,
      class: :invalid,
      fields: [message: "Invalid codec document", reason: nil, details: %{}]

    @type reason ::
            :bytes
            | :collection
            | :depth
            | :duplicate_key
            | :invalid_json
            | :json
            | :list
            | :nodes
    @type t :: %__MODULE__{
            message: String.t(),
            reason: reason(),
            path: [String.t() | non_neg_integer()],
            details: map()
          }
  end

  @doc false
  def maximum_depth, do: @maximum_depth

  @doc false
  def maximum_collection_size, do: @maximum_collection_size

  @doc false
  def maximum_document_nodes, do: @maximum_document_nodes

  @doc "Parses one bounded JSON document without losing duplicate-key information."
  @spec decode_json(term(), pos_integer()) :: {:ok, term()} | {:error, Error.t()}
  def decode_json(json, maximum_bytes)
      when is_binary(json) and is_integer(maximum_bytes) and maximum_bytes > 0 and
             byte_size(json) <= maximum_bytes do
    decoders = [
      object_start: fn _old -> [] end,
      object_push: fn key, value, pairs -> [{key, value} | pairs] end,
      object_finish: fn pairs, old -> {{:jido_codec_object, Enum.reverse(pairs)}, old} end,
      string: &:binary.copy/1
    ]

    case JSON.decode(json, :ok, decoders) do
      {document, :ok, ""} ->
        case plain_json(document, [], 0, @maximum_document_nodes) do
          {:ok, document, _remaining} -> {:ok, document}
          {:error, %Error{}} = error -> error
        end

      {_document, :ok, rest} ->
        offset = byte_size(json) - byte_size(rest)
        error(:invalid_json, "invalid JSON byte at offset #{offset}")

      {:error, reason} ->
        error(:invalid_json, json_error_message(reason))
    end
  end

  def decode_json(_json, maximum_bytes)
      when is_integer(maximum_bytes) and maximum_bytes > 0 do
    error(
      :invalid_json,
      "expected a JSON string of at most #{maximum_bytes} bytes",
      %{maximum_bytes: maximum_bytes}
    )
  end

  def decode_json(_json, maximum_bytes) do
    raise ArgumentError,
          "maximum_bytes must be a positive integer, got: #{inspect(maximum_bytes)}"
  end

  @doc "Checks the resource limits of one complete codec document."
  @spec check(term()) :: :ok | {:error, Error.t()}
  def check(document) do
    case count(document, 0, @maximum_document_nodes) do
      {:ok, _remaining} -> :ok
      {:error, exception} -> {:error, exception}
    end
  end

  @doc "Checks structure, JSON compatibility, and the exact encoded byte size."
  @spec check_json(term(), pos_integer()) :: :ok | {:error, Error.t()}
  def check_json(document, maximum_bytes) when is_integer(maximum_bytes) and maximum_bytes > 0 do
    with :ok <- check(document), do: json_round_trip(document, maximum_bytes)
  end

  def check_json(_document, maximum_bytes) do
    raise ArgumentError,
          "maximum_bytes must be a positive integer, got: #{inspect(maximum_bytes)}"
  end

  defp count(_value, _depth, remaining) when remaining <= 0,
    do:
      error(:nodes, "codec document exceeds its total node limit", %{
        maximum_nodes: @maximum_document_nodes
      })

  defp count(_value, depth, _remaining) when depth > @maximum_depth,
    do:
      error(:depth, "codec document exceeds its nesting limit", %{
        maximum_depth: @maximum_depth
      })

  defp count(value, depth, remaining) when is_list(value) do
    cond do
      List.improper?(value) ->
        error(:list, "codec document must contain proper lists")

      length(value) > @maximum_collection_size ->
        error(:collection, "codec document collection exceeds its size limit", %{
          maximum_size: @maximum_collection_size
        })

      true ->
        Enum.reduce_while(value, {:ok, remaining - 1}, fn item, {:ok, left} ->
          case count(item, depth + 1, left) do
            {:ok, next} -> {:cont, {:ok, next}}
            {:error, exception} -> {:halt, {:error, exception}}
          end
        end)
    end
  end

  defp count(value, depth, remaining) when is_map(value) and not is_struct(value) do
    if map_size(value) > @maximum_collection_size do
      error(:collection, "codec document collection exceeds its size limit", %{
        maximum_size: @maximum_collection_size
      })
    else
      Enum.reduce_while(value, {:ok, remaining - 1}, fn {key, item}, {:ok, left} ->
        with {:ok, left} <- count(key, depth + 1, left),
             {:ok, left} <- count(item, depth + 1, left) do
          {:cont, {:ok, left}}
        else
          {:error, exception} -> {:halt, {:error, exception}}
        end
      end)
    end
  end

  defp count(_value, _depth, remaining), do: {:ok, remaining - 1}

  defp plain_json(_value, _path, _depth, remaining) when remaining <= 0,
    do:
      error(:nodes, "codec document exceeds its total node limit", %{
        maximum_nodes: @maximum_document_nodes
      })

  defp plain_json(_value, _path, depth, _remaining) when depth > @maximum_depth,
    do:
      error(:depth, "codec document exceeds its nesting limit", %{
        maximum_depth: @maximum_depth
      })

  defp plain_json({:jido_codec_object, pairs}, path, depth, remaining) do
    cond do
      length(pairs) > @maximum_collection_size ->
        collection_error()

      key = duplicate_key(pairs) ->
        error(
          :duplicate_key,
          "JSON object contains a duplicate key",
          %{key: key},
          path ++ [key]
        )

      true ->
        Enum.reduce_while(pairs, {:ok, %{}, remaining - 1}, fn {key, value}, {:ok, result, left} ->
          with {:ok, _key, left} <- plain_json(key, path, depth + 1, left),
               {:ok, value, left} <- plain_json(value, path ++ [key], depth + 1, left) do
            {:cont, {:ok, Map.put(result, key, value), left}}
          else
            {:error, %Error{}} = error -> {:halt, error}
          end
        end)
    end
  end

  defp plain_json(values, path, depth, remaining) when is_list(values) do
    if length(values) > @maximum_collection_size do
      collection_error()
    else
      values
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, [], remaining - 1}, fn {value, index}, {:ok, result, left} ->
        case plain_json(value, path ++ [index], depth + 1, left) do
          {:ok, value, left} -> {:cont, {:ok, [value | result], left}}
          {:error, %Error{}} = error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, result, left} -> {:ok, Enum.reverse(result), left}
        {:error, %Error{}} = error -> error
      end
    end
  end

  defp plain_json(value, _path, _depth, remaining), do: {:ok, value, remaining - 1}

  defp collection_error do
    error(:collection, "codec document collection exceeds its size limit", %{
      maximum_size: @maximum_collection_size
    })
  end

  defp duplicate_key(pairs) do
    Enum.reduce_while(pairs, MapSet.new(), fn {key, _value}, seen ->
      if MapSet.member?(seen, key),
        do: {:halt, key},
        else: {:cont, MapSet.put(seen, key)}
    end)
    |> case do
      %MapSet{} -> nil
      key -> key
    end
  end

  defp json_error_message({:unexpected_end, offset}),
    do: "unexpected end of JSON at offset #{offset}"

  defp json_error_message({:invalid_byte, offset, byte}),
    do: "invalid JSON byte #{inspect(byte)} at offset #{offset}"

  defp json_error_message({:unexpected_sequence, offset, bytes}),
    do: "invalid JSON sequence #{inspect(bytes)} at offset #{offset}"

  defp json_error_message(reason), do: "invalid JSON: #{inspect(reason)}"

  defp json_round_trip(document, maximum_bytes) do
    json = JSON.encode!(document)

    if byte_size(json) > maximum_bytes do
      error(:bytes, "codec document exceeds its JSON byte limit", %{
        bytes: byte_size(json),
        maximum_bytes: maximum_bytes
      })
    else
      case JSON.decode(json) do
        {:ok, ^document} -> :ok
        {:ok, _changed} -> json_error("document changes during JSON encoding")
        {:error, reason} -> json_error(inspect(reason))
      end
    end
  rescue
    exception -> json_error(Exception.message(exception))
  catch
    kind, reason -> json_error(inspect({kind, reason}, limit: 20, printable_limit: 1_000))
  end

  defp json_error(reason),
    do: error(:json, "codec document is not JSON-compatible", %{reason: reason})

  defp error(reason, message, details \\ %{}, path \\ []),
    do: {:error, Error.exception(reason: reason, message: message, path: path, details: details)}
end
