defmodule Jido.Flow.Error do
  @moduledoc """
  Defines and normalizes errors owned by Jido Flows.

  Flow errors cover authoring data, compilation, native Runic coordination,
  and Flow execution state. An Action failure inside a Flow keeps its original
  `Jido.Action.Error` type.
  """

  use Splode,
    error_classes: [
      invalid: __MODULE__.Invalid,
      execution: __MODULE__.Execution,
      internal: __MODULE__.Internal
    ],
    unknown_error: __MODULE__.Internal.UnknownError,
    merge_with: [Jido.Action.Error]

  alias Jido.Action.Error, as: ActionError

  @type details_input :: map() | keyword()
  @type error_map :: ActionError.error_map()

  defmodule Invalid do
    @moduledoc "An ordered group of invalid Flow definition errors."
    use Splode.ErrorClass, class: :invalid

    @type t :: %__MODULE__{errors: [Exception.t()]}
  end

  defmodule Execution do
    @moduledoc false
    use Splode.ErrorClass, class: :execution
  end

  defmodule Internal do
    @moduledoc false
    use Splode.ErrorClass, class: :internal

    defmodule UnknownError do
      @moduledoc false
      use Splode.Error,
        class: :internal,
        fields: [message: "Unknown Flow error", error: nil, details: %{}]

      @type t :: %__MODULE__{
              message: String.t(),
              error: any() | nil,
              details: map()
            }

      @spec message(t()) :: String.t()
      def message(%{error: error}) when not is_nil(error), do: normalize_message(error)
      def message(%{message: message}), do: message

      defp normalize_message(message) when is_binary(message), do: message
      defp normalize_message(message) when is_atom(message), do: Atom.to_string(message)
      defp normalize_message(message), do: inspect(message)
    end
  end

  defmodule InvalidDefinitionError do
    @moduledoc "Error for invalid canonical Flow data or authoring input."
    use Splode.Error,
      class: :invalid,
      fields: [message: "Invalid Flow definition", details: %{}]

    @type t :: %__MODULE__{message: String.t(), details: map()}
  end

  defmodule InvalidExecutionError do
    @moduledoc "Error for invalid Flow execution input or state."
    use Splode.Error,
      class: :invalid,
      fields: [message: "Invalid Flow execution", details: %{}]

    @type t :: %__MODULE__{message: String.t(), details: map()}
  end

  defmodule ExecutionFailureError do
    @moduledoc "Error for native Flow execution failures."
    use Splode.Error,
      class: :execution,
      fields: [message: "Flow execution failed", flow: nil, details: %{}]

    @type t :: %__MODULE__{
            message: String.t(),
            flow: String.t() | nil,
            details: map()
          }
  end

  defmodule TimeoutError do
    @moduledoc "Error for a Flow execution timeout."
    use Splode.Error,
      class: :execution,
      fields: [message: "Flow execution timed out", flow: nil, timeout: nil, details: %{}]

    @type t :: %__MODULE__{
            message: String.t(),
            flow: String.t() | module() | nil,
            timeout: non_neg_integer() | nil,
            details: map()
          }
  end

  defmodule InternalError do
    @moduledoc "Error for an unexpected internal Flow failure."
    use Splode.Error,
      class: :internal,
      fields: [message: "Internal Flow error", details: %{}]

    @type t :: %__MODULE__{message: String.t(), details: map()}
  end

  @doc "Creates an invalid Flow definition error."
  @spec validation_error(String.t(), details_input()) :: InvalidDefinitionError.t()
  def validation_error(message, details \\ %{}) do
    InvalidDefinitionError.exception(message: message, details: normalize_input(details))
  end

  @doc false
  @spec prefix_path(term(), list()) :: term()
  def prefix_path(%{details: details} = error, path) when is_map(details) do
    %{error | details: Map.put(details, :path, path ++ Map.get(details, :path, []))}
  end

  def prefix_path(error, _path), do: error

  @doc "Creates an invalid Flow execution input or state error."
  @spec invalid_execution_error(String.t(), details_input()) :: InvalidExecutionError.t()
  def invalid_execution_error(message, details \\ %{}) do
    InvalidExecutionError.exception(message: message, details: normalize_input(details))
  end

  @doc "Creates a Flow execution failure."
  @spec execution_error(String.t(), details_input()) :: ExecutionFailureError.t()
  def execution_error(message, details \\ %{}) do
    ExecutionFailureError.exception(message: message, details: normalize_input(details))
  end

  @doc "Creates a Flow timeout error."
  @spec timeout_error(String.t(), details_input()) :: TimeoutError.t()
  def timeout_error(message, details \\ %{}) do
    details = normalize_input(details)

    TimeoutError.exception(
      message: message,
      flow: Map.get(details, :flow),
      timeout: Map.get(details, :timeout),
      details: details
    )
  end

  @doc "Creates an internal Flow error."
  @spec internal_error(String.t(), details_input()) :: InternalError.t()
  def internal_error(message, details \\ %{}) do
    InternalError.exception(message: message, details: normalize_input(details))
  end

  @doc """
  Converts a Flow or Action error into its public map.

  Detail values stay unchanged. A caller that sends the map through JSON or
  another transport must convert its own detail values for that transport.
  Members of an Invalid error group become public maps recursively.
  Values inside a leaf details map, including nested exceptions and
  stacktraces, stay unchanged.
  """
  @spec to_map(term()) :: error_map()
  def to_map({:error, reason, _effects}), do: to_map(reason)
  def to_map({:error, reason}), do: to_map(reason)

  def to_map(%InvalidDefinitionError{} = error) do
    error_map(:flow_definition_error, error.message, error.details, false)
  end

  def to_map(%InvalidExecutionError{} = error) do
    error_map(:flow_invalid_execution, error.message, error.details, false)
  end

  def to_map(%ExecutionFailureError{} = error) do
    details = maybe_put(error.details, :flow, error.flow)

    error_map(
      :flow_execution_error,
      error.message,
      details,
      retryable?(error)
    )
  end

  def to_map(%TimeoutError{} = error) do
    details =
      error.details
      |> maybe_put(:flow, error.flow)
      |> maybe_put(:timeout, error.timeout)

    error_map(
      :flow_timeout,
      error.message,
      details,
      retryable?(error)
    )
  end

  def to_map(%InternalError{} = error) do
    error_map(:flow_internal_error, error.message, error.details, false)
  end

  def to_map(%Internal.UnknownError{} = error) do
    error_map(:flow_internal_error, Exception.message(error), error.details, false)
  end

  def to_map(%Invalid{errors: errors}) do
    error_map(
      :flow_definition_error,
      "Invalid Flow",
      error_list_details(errors),
      false
    )
  end

  def to_map(%Execution{errors: errors}) do
    error_map(
      :flow_execution_error,
      "Flow execution failed",
      error_list_details(errors),
      false
    )
  end

  def to_map(%Internal{errors: errors}) do
    error_map(
      :flow_internal_error,
      "Internal Flow error",
      error_list_details(errors),
      false
    )
  end

  def to_map(error), do: ActionError.to_map(error)

  @doc "Returns whether a Flow or Action error is retryable."
  @spec retryable?(term()) :: boolean()
  def retryable?({:error, reason, _effects}), do: retryable?(reason)
  def retryable?({:error, reason}), do: retryable?(reason)

  def retryable?(%ExecutionFailureError{details: %{retry: retry}})
      when is_boolean(retry),
      do: retry

  def retryable?(%ExecutionFailureError{}), do: false
  def retryable?(%TimeoutError{details: %{retry: retry}}) when is_boolean(retry), do: retry
  def retryable?(%TimeoutError{}), do: false
  def retryable?(%InvalidDefinitionError{}), do: false
  def retryable?(%InvalidExecutionError{}), do: false
  def retryable?(%InternalError{}), do: false
  def retryable?(%Internal.UnknownError{}), do: false
  def retryable?(%Invalid{}), do: false
  def retryable?(%Execution{}), do: false
  def retryable?(%Internal{}), do: false
  def retryable?(error), do: ActionError.retryable?(error)

  defp error_map(type, message, details, retryable?) do
    %{type: type, message: message, details: details, retryable?: retryable?}
  end

  defp error_list_details(errors), do: %{errors: Enum.map(errors, &to_map/1)}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_input(details) when is_map(details) and not is_struct(details), do: details

  defp normalize_input(details) when is_list(details),
    do: if(Keyword.keyword?(details), do: Map.new(details), else: %{})

  defp normalize_input(_details), do: %{}
end
