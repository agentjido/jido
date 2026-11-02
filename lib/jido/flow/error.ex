defmodule Jido.Flow.Error do
  @moduledoc "Defines errors for invalid Flow definitions."

  defmodule InvalidError do
    @moduledoc "An ordered set of invalid Flow document errors."

    defexception message: "Invalid Flow document", errors: []

    @type t :: %__MODULE__{message: String.t(), errors: [Exception.t()]}
  end

  defmodule InvalidDefinitionError do
    @moduledoc "An invalid canonical Flow definition or authoring value."

    defexception message: "Invalid Flow definition", details: %{}

    @type t :: %__MODULE__{message: String.t(), details: map()}
  end

  @type details_input :: map() | keyword()

  @doc "Creates an invalid Flow definition error."
  @spec validation_error(String.t(), details_input()) :: InvalidDefinitionError.t()
  def validation_error(message, details \\ %{}) do
    InvalidDefinitionError.exception(message: message, details: normalize_details(details))
  end

  @doc false
  @spec prefix_path(term(), list()) :: term()
  def prefix_path(%{details: details} = error, path) when is_map(details) do
    %{error | details: Map.put(details, :path, path ++ Map.get(details, :path, []))}
  end

  def prefix_path(error, _path), do: error

  @doc "Converts a Flow definition error to stable public data."
  @spec to_map(term()) :: map()
  def to_map(%InvalidDefinitionError{} = error) do
    %{
      type: :flow_definition_error,
      message: error.message,
      details: error.details,
      retryable?: false
    }
  end

  def to_map(error) do
    %{
      type: :flow_definition_error,
      message: error_message(error),
      details: %{},
      retryable?: false
    }
  end

  defp error_message(%{__exception__: true} = error), do: Exception.message(error)
  defp error_message(error), do: inspect(error)

  defp normalize_details(details) when is_map(details) and not is_struct(details), do: details

  defp normalize_details(details) when is_list(details) do
    if Keyword.keyword?(details), do: Map.new(details), else: %{}
  end

  defp normalize_details(_details), do: %{}
end
