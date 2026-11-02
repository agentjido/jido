defmodule Jido.Action.Error do
  @moduledoc """
  Defines and normalizes errors produced by Jido Actions.

  The public boundary is intentionally small. Concrete Action errors keep their
  canonical type, details, and retry policy. Any unsupported value becomes a
  non-retryable execution error with no structured details.

  Errors are non-retryable by default. Set `details.retry` to `true` only when
  another attempt is safe. `Jido.Exec` retries a failed attempt only when the
  caller sets `max_attempts` and `retryable?/1` returns `true`.
  """

  use Splode,
    error_classes: [
      invalid: __MODULE__.Invalid,
      execution: __MODULE__.Execution,
      config: __MODULE__.Config,
      internal: __MODULE__.Internal
    ],
    unknown_error: __MODULE__.Internal.UnknownError

  @type details_input :: map() | keyword()
  @type error_map :: %{
          type: atom(),
          message: String.t(),
          details: map(),
          retryable?: boolean()
        }

  defmodule Invalid do
    @moduledoc false
    use Splode.ErrorClass, class: :invalid
  end

  defmodule Execution do
    @moduledoc false
    use Splode.ErrorClass, class: :execution
  end

  defmodule Config do
    @moduledoc false
    use Splode.ErrorClass, class: :config
  end

  defmodule Internal do
    @moduledoc false
    use Splode.ErrorClass, class: :internal

    defmodule UnknownError do
      @moduledoc false
      use Splode.Error,
        class: :internal,
        fields: [message: "Unknown error", error: nil, details: %{}]

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

  defmodule InvalidInputError do
    @moduledoc "Error for invalid input parameters."
    use Splode.Error,
      class: :invalid,
      fields: [message: "Invalid input", field: nil, value: nil, details: %{}]

    @type t :: %__MODULE__{
            message: String.t(),
            field: atom() | nil,
            value: any() | nil,
            details: map()
          }
  end

  defmodule ExecutionFailureError do
    @moduledoc "Error for Action execution failures."
    use Splode.Error,
      class: :execution,
      fields: [message: "Execution failed", details: %{}]

    @type t :: %__MODULE__{message: String.t(), details: map()}
  end

  defmodule TimeoutError do
    @moduledoc "Error for Action timeouts."
    use Splode.Error,
      class: :execution,
      fields: [message: "Action timed out", timeout: nil, details: %{}]

    @type t :: %__MODULE__{
            message: String.t(),
            timeout: non_neg_integer() | nil,
            details: map()
          }
  end

  defmodule ConfigurationError do
    @moduledoc "Error for invalid Action configuration."
    use Splode.Error,
      class: :config,
      fields: [message: "Configuration error", details: %{}]

    @type t :: %__MODULE__{message: String.t(), details: map()}
  end

  defmodule InternalError do
    @moduledoc "Error for unexpected internal failures."
    use Splode.Error,
      class: :internal,
      fields: [message: "Internal error", details: %{}]

    @type t :: %__MODULE__{message: String.t(), details: map()}
  end

  @doc "Creates an invalid-input error."
  @spec validation_error(String.t(), details_input()) :: InvalidInputError.t()
  def validation_error(message, details \\ %{}) do
    details = normalize_constructor_details(details)

    InvalidInputError.exception(
      message: message,
      field: Map.get(details, :field),
      value: Map.get(details, :value),
      details: details
    )
  end

  @doc "Creates an Action execution error."
  @spec execution_error(String.t(), details_input()) :: ExecutionFailureError.t()
  def execution_error(message, details \\ %{}) do
    ExecutionFailureError.exception(
      message: message,
      details: normalize_constructor_details(details)
    )
  end

  @doc "Creates an Action configuration error."
  @spec config_error(String.t(), details_input()) :: ConfigurationError.t()
  def config_error(message, details \\ %{}) do
    ConfigurationError.exception(
      message: message,
      details: normalize_constructor_details(details)
    )
  end

  @doc "Creates an Action timeout error."
  @spec timeout_error(String.t(), details_input()) :: TimeoutError.t()
  def timeout_error(message, details \\ %{}) do
    details = normalize_constructor_details(details)

    TimeoutError.exception(
      message: message,
      timeout: Map.get(details, :timeout),
      details: details
    )
  end

  @doc "Creates an internal Action error."
  @spec internal_error(String.t(), details_input()) :: InternalError.t()
  def internal_error(message, details \\ %{}) do
    InternalError.exception(
      message: message,
      details: normalize_constructor_details(details)
    )
  end

  @doc """
  Converts an Action error into its public map.

  Unsupported values become conservative execution errors. They cannot select
  a canonical type, add structured details, or request a retry.

  Detail values stay unchanged. A caller that sends the map through JSON or
  another transport must convert its own detail values for that transport.
  The map omits the exception's top-level stacktrace.
  """
  @spec to_map(term()) :: error_map()
  def to_map({:error, reason, _effects}), do: to_map(reason)
  def to_map({:error, reason}), do: to_map(reason)

  def to_map(%InvalidInputError{} = error) do
    %{
      type: :validation_error,
      message: error.message,
      details:
        error.details
        |> maybe_put(:field, error.field)
        |> maybe_put(:value, error.value),
      retryable?: false
    }
  end

  def to_map(%ExecutionFailureError{} = error) do
    error_map(:execution_error, error.message, error.details, retryable?(error))
  end

  def to_map(%TimeoutError{} = error) do
    error_map(
      :timeout,
      error.message,
      maybe_put(error.details, :timeout, error.timeout),
      retryable?(error)
    )
  end

  def to_map(%ConfigurationError{} = error) do
    error_map(:configuration_error, error.message, error.details, false)
  end

  def to_map(%InternalError{} = error) do
    error_map(:internal_error, error.message, error.details, false)
  end

  def to_map(%Internal.UnknownError{} = error) do
    error_map(:internal_error, Exception.message(error), error.details, false)
  end

  def to_map(reason) do
    error_map(:execution_error, error_message(reason), %{}, false)
  end

  @doc """
  Returns whether a concrete Action error is retryable.

  A Boolean `details.retry` value controls the result for execution and timeout
  errors. All errors are non-retryable by default. Unsupported values are never
  retryable.
  """
  @spec retryable?(term()) :: boolean()
  def retryable?({:error, reason, _effects}), do: retryable?(reason)
  def retryable?({:error, reason}), do: retryable?(reason)
  def retryable?(%InvalidInputError{}), do: false
  def retryable?(%ConfigurationError{}), do: false
  def retryable?(%InternalError{}), do: false
  def retryable?(%Internal.UnknownError{}), do: false
  def retryable?(%TimeoutError{details: %{retry: retry}}) when is_boolean(retry), do: retry
  def retryable?(%TimeoutError{}), do: false

  def retryable?(%ExecutionFailureError{details: %{retry: retry}})
      when is_boolean(retry),
      do: retry

  def retryable?(%ExecutionFailureError{}), do: false
  def retryable?(_reason), do: false

  defp normalize_constructor_details(details)
       when is_map(details) and not is_struct(details),
       do: details

  defp normalize_constructor_details(details) when is_list(details) do
    if Keyword.keyword?(details), do: Map.new(details), else: %{}
  end

  defp normalize_constructor_details(_details), do: %{}

  defp error_map(type, message, details, retryable?) do
    %{type: type, message: message, details: details, retryable?: retryable?}
  end

  defp error_message(message) when is_binary(message), do: message
  defp error_message(message) when is_atom(message), do: Atom.to_string(message)
  defp error_message(message), do: inspect(message)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
