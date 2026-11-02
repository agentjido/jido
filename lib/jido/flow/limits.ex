defmodule Jido.Flow.Limits do
  @moduledoc false

  alias Jido.Flow.Error

  require Jido.Authoring.Limits

  @maximum_collection_size Jido.Authoring.Limits.maximum_collection_size()

  @doc false
  @spec collection(list() | map(), atom()) :: :ok | {:error, Exception.t()}
  def collection(values, field) when is_list(values) do
    if length(values) <= @maximum_collection_size,
      do: :ok,
      else: collection_error(field)
  end

  def collection(values, field) when is_map(values) and not is_struct(values) do
    if map_size(values) <= @maximum_collection_size,
      do: :ok,
      else: collection_error(field)
  end

  defp collection_error(field) do
    {:error,
     Error.validation_error("Flow collection exceeds its size limit", %{
       reason: :collection,
       field: field,
       maximum_size: @maximum_collection_size
     })}
  end
end
