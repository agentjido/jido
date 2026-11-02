defmodule Jido.Authoring.Document do
  @moduledoc """
  Enforces resource limits on one complete authoring document.

  `check/1` limits nesting, collection size, and the total number of nodes.
  `check_json/2` also checks JSON compatibility and the encoded byte size.
  Neither function validates the document owner's fields or portable values.
  """

  require Jido.Authoring.Limits

  @maximum_depth Jido.Authoring.Limits.maximum_depth()
  @maximum_collection_size Jido.Authoring.Limits.maximum_collection_size()
  @maximum_document_nodes Jido.Authoring.Limits.maximum_document_nodes()
  defmodule Error do
    @moduledoc "An authoring document that exceeds a resource or shape limit."
    use Splode.Error,
      class: :invalid,
      fields: [message: "Invalid authoring document", reason: nil, details: %{}]

    @type reason :: :bytes | :collection | :depth | :json | :list | :nodes
    @type t :: %__MODULE__{message: String.t(), reason: reason(), details: map()}
  end

  @doc "Checks the resource limits of one complete authoring document."
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
      error(:nodes, "authoring document exceeds its total node limit", %{
        maximum_nodes: @maximum_document_nodes
      })

  defp count(_value, depth, _remaining) when depth > @maximum_depth,
    do:
      error(:depth, "authoring document exceeds its nesting limit", %{
        maximum_depth: @maximum_depth
      })

  defp count(value, depth, remaining) when is_list(value) do
    cond do
      List.improper?(value) ->
        error(:list, "authoring document must contain proper lists")

      length(value) > @maximum_collection_size ->
        error(:collection, "authoring document collection exceeds its size limit", %{
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
      error(:collection, "authoring document collection exceeds its size limit", %{
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

  defp json_round_trip(document, maximum_bytes) do
    json = Jason.encode!(document, maps: :strict)

    if byte_size(json) > maximum_bytes do
      error(:bytes, "authoring document exceeds its JSON byte limit", %{
        bytes: byte_size(json),
        maximum_bytes: maximum_bytes
      })
    else
      case Jason.decode!(json, strings: :copy) do
        ^document -> :ok
        _changed -> json_error("document changes during JSON encoding")
      end
    end
  rescue
    exception -> json_error(Exception.message(exception))
  catch
    kind, reason -> json_error(inspect({kind, reason}, limit: 20, printable_limit: 1_000))
  end

  defp json_error(reason),
    do: error(:json, "authoring document is not JSON-compatible", %{reason: reason})

  defp error(reason, message, details \\ %{}),
    do: {:error, Error.exception(reason: reason, message: message, details: details)}
end
