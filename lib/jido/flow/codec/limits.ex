defmodule Jido.Flow.Codec.Limits do
  @moduledoc false
  alias Jido.Authoring.Document
  alias Jido.Authoring.Document.Error, as: DocumentError
  alias Jido.Flow.Error

  require Jido.Authoring.Limits

  @maximum_depth Jido.Authoring.Limits.maximum_depth()
  @maximum_collection_size Jido.Authoring.Limits.maximum_collection_size()
  @limit_errors %{
    depth: "stored Flow exceeds its nesting limit",
    collection: "stored Flow collection exceeds its size limit",
    nodes: "stored Flow exceeds its total node limit"
  }

  @doc false
  @spec depth(non_neg_integer()) :: :ok | {:error, Exception.t()}
  def depth(value) when value <= @maximum_depth, do: :ok
  def depth(_value), do: limit_error(:depth, %{maximum_depth: @maximum_depth})

  @doc false
  @spec size(term()) :: :ok | {:error, Exception.t()}
  def size(values) when length(values) <= @maximum_collection_size, do: :ok

  def size(values)
      when is_map(values) and map_size(values) <= @maximum_collection_size,
      do: :ok

  def size(_values),
    do: limit_error(:collection, %{maximum_size: @maximum_collection_size})

  @doc false
  @spec check(term()) :: :ok | {:error, Exception.t()}
  def check(document) do
    case Document.check(document) do
      :ok -> :ok
      {:error, %DocumentError{} = exception} -> document_error(exception)
    end
  end

  defp document_error(%DocumentError{reason: :list}),
    do: {:error, Error.validation_error("stored Flow data must contain proper lists")}

  defp document_error(%DocumentError{reason: reason, details: details}),
    do: limit_error(reason, details)

  defp limit_error(reason, details) do
    message = Map.fetch!(@limit_errors, reason)
    {:error, Error.validation_error(message, details)}
  end
end
