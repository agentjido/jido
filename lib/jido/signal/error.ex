defmodule Jido.Signal.Error do
  @moduledoc """
  Canonical error taxonomy, normalization, retryability, and public serialization
  for Jido Signal.

  Use this module to create package-local exceptions, normalize foreign failures,
  and serialize public error payloads through `to_map/1`.
  """

  alias Jido.Signal.Sanitizer

  use Splode,
    error_classes: [
      invalid: Invalid,
      execution: Execution,
      routing: Routing,
      timeout: Timeout,
      internal: Internal
    ],
    unknown_error: Jido.Signal.Error.Internal.UnknownError,
    filter_stacktraces: [Jido.Signal, "Jido.Signal."]

  @type detail_map :: map()
  @type details_input :: term()

  defmodule Invalid do
    @moduledoc "Splode error class for invalid inputs and validation failures."

    use Splode.ErrorClass, class: :invalid
  end

  defmodule Execution do
    @moduledoc "Splode error class for runtime execution failures."

    use Splode.ErrorClass, class: :execution
  end

  defmodule Routing do
    @moduledoc "Splode error class for routing failures."

    use Splode.ErrorClass, class: :routing
  end

  defmodule Timeout do
    @moduledoc "Splode error class for timeout failures."

    use Splode.ErrorClass, class: :timeout
  end

  defmodule Internal do
    @moduledoc "Splode error class for unexpected internal failures."

    use Splode.ErrorClass, class: :internal

    defmodule UnknownError do
      @moduledoc false

      use Splode.Error, class: :internal, fields: [:message, :details]

      @impl true
      def exception(opts) do
        opts
        |> Keyword.put_new(:message, "Unknown error")
        |> Keyword.put_new(:details, %{})
        |> super()
      end
    end
  end

  defmodule InvalidInputError do
    @moduledoc "Error for invalid input parameters."

    use Splode.Error, class: :invalid, fields: [:message, :field, :value, :details]

    @impl true
    def exception(opts) do
      opts
      |> Keyword.put_new(:message, "Invalid input")
      |> Keyword.put_new(:details, %{})
      |> super()
    end
  end

  defmodule ExecutionFailureError do
    @moduledoc "Error for runtime signal processing failures."

    use Splode.Error, class: :execution, fields: [:message, :details]

    @impl true
    def exception(opts) do
      opts
      |> Keyword.put_new(:message, "Signal processing failed")
      |> Keyword.put_new(:details, %{})
      |> super()
    end
  end

  defmodule RoutingError do
    @moduledoc "Error for routing failures."

    use Splode.Error, class: :routing, fields: [:message, :target, :details]

    @impl true
    def exception(opts) do
      opts
      |> Keyword.put_new(:message, "Signal routing failed")
      |> Keyword.put_new(:details, %{})
      |> super()
    end
  end

  defmodule TimeoutError do
    @moduledoc "Error for timeout failures."

    use Splode.Error, class: :timeout, fields: [:message, :timeout, :details]

    @impl true
    def exception(opts) do
      opts
      |> Keyword.put_new(:message, "Signal processing timed out")
      |> Keyword.put_new(:details, %{})
      |> super()
    end
  end

  defmodule DispatchError do
    @moduledoc "Error for dispatch failures."

    use Splode.Error, class: :execution, fields: [:message, :details]

    @impl true
    def exception(opts) do
      opts
      |> Keyword.put_new(:message, "Signal dispatch failed")
      |> Keyword.put_new(:details, %{})
      |> super()
    end
  end

  defmodule InternalError do
    @moduledoc "Error for unexpected internal failures."

    use Splode.Error, class: :internal, fields: [:message, :details]

    @impl true
    def exception(opts) do
      opts
      |> Keyword.put_new(:message, "Internal error")
      |> Keyword.put_new(:details, %{})
      |> super()
    end
  end

  @doc """
  Creates a validation error for invalid input parameters.
  """
  @spec validation_error(String.t(), details_input()) :: %InvalidInputError{}
  def validation_error(message, details \\ %{}) do
    details = normalize_details(details)

    InvalidInputError.exception(
      message: message,
      field: Map.get(details, :field),
      value: Map.get(details, :value),
      details: details,
      splode: __MODULE__
    )
  end

  @doc """
  Creates an execution error for signal processing failures.
  """
  @spec execution_error(String.t(), details_input()) :: %ExecutionFailureError{}
  def execution_error(message, details \\ %{}) do
    ExecutionFailureError.exception(
      message: message,
      details: normalize_details(details),
      splode: __MODULE__
    )
  end

  @doc """
  Creates a routing error for signal routing failures.
  """
  @spec routing_error(String.t(), details_input()) :: %RoutingError{}
  def routing_error(message, details \\ %{}) do
    details = normalize_details(details)

    RoutingError.exception(
      message: message,
      target: Map.get(details, :target),
      details: details,
      splode: __MODULE__
    )
  end

  @doc """
  Creates a timeout error for signal processing timeouts.
  """
  @spec timeout_error(String.t(), details_input()) :: %TimeoutError{}
  def timeout_error(message, details \\ %{}) do
    details = normalize_details(details)

    TimeoutError.exception(
      message: message,
      timeout: Map.get(details, :timeout),
      details: details,
      splode: __MODULE__
    )
  end

  @doc """
  Creates a dispatch error for signal dispatch failures.
  """
  @spec dispatch_error(String.t(), details_input()) :: %DispatchError{}
  def dispatch_error(message, details \\ %{}) do
    DispatchError.exception(
      message: message,
      details: normalize_details(details),
      splode: __MODULE__
    )
  end

  @doc """
  Creates an internal error.
  """
  @spec internal_error(String.t(), details_input()) :: %InternalError{}
  def internal_error(message, details \\ %{}) do
    InternalError.exception(
      message: message,
      details: normalize_details(details),
      splode: __MODULE__
    )
  end

  @doc """
  Normalizes a foreign failure into a package-local error.
  """
  @spec normalize(term()) :: Exception.t()
  def normalize({:error, reason}), do: normalize(reason)

  def normalize(%struct{} = error)
      when struct in [
             InvalidInputError,
             ExecutionFailureError,
             RoutingError,
             TimeoutError,
             DispatchError,
             InternalError,
             Internal.UnknownError,
             Invalid,
             Execution,
             Routing,
             Timeout,
             Internal
           ] do
    error
  end

  def normalize(%ArgumentError{} = error) do
    validation_error(Exception.message(error), %{reason: Exception.message(error)})
  end

  def normalize(%RuntimeError{} = error) do
    execution_error(Exception.message(error), %{reason: Exception.message(error)})
  end

  def normalize(%_{} = error) when is_exception(error) do
    internal_error(Exception.message(error), %{reason: error})
  end

  def normalize(error) when is_binary(error) do
    internal_error(error, %{reason: error})
  end

  def normalize(error) when is_atom(error) do
    internal_error("Signal processing failed", %{reason: error})
  end

  def normalize(error) do
    internal_error("Signal processing failed", %{reason: error})
  end

  @doc """
  Returns the stable machine-readable error type.
  """
  @spec type(term()) :: atom()
  def type(%InvalidInputError{}), do: :invalid_input_error
  def type(%ExecutionFailureError{}), do: :execution_failure_error
  def type(%RoutingError{}), do: :routing_error
  def type(%TimeoutError{}), do: :timeout_error
  def type(%DispatchError{}), do: :dispatch_error
  def type(%InternalError{}), do: :internal_error
  def type(%Internal.UnknownError{}), do: :unknown_error
  def type(%Invalid{}), do: :invalid
  def type(%Execution{}), do: :execution
  def type(%Routing{}), do: :routing
  def type(%Timeout{}), do: :timeout
  def type(%Internal{}), do: :internal
  def type(error), do: error |> normalize() |> type()

  @doc """
  Returns whether a failure is retryable according to the package policy.
  """
  @spec retryable?(term()) :: boolean()
  def retryable?(%TimeoutError{}), do: true

  def retryable?(%DispatchError{details: details}) do
    retryable_from_details?(details)
  end

  def retryable?(%ExecutionFailureError{details: details}) do
    retryable_from_details?(details)
  end

  def retryable?(%InternalError{details: details}) do
    retryable_from_details?(details)
  end

  def retryable?(%Internal.UnknownError{details: details}) do
    retryable_from_details?(details)
  end

  def retryable?(%{errors: errors}) when is_list(errors) and is_integer(length(errors)) do
    Enum.any?(errors, &retryable?/1)
  end

  def retryable?(_error), do: false

  @doc """
  Serializes a public error payload through the canonical package adapter.
  """
  @spec to_map(term()) :: map()
  def to_map(error) do
    error = normalize(error)

    %{
      type: type(error),
      message: public_message(error),
      details: transport_details(Map.get(error, :details, %{})),
      retryable?: retryable?(error)
    }
  end

  defp public_message(%Invalid{}), do: "Invalid input"
  defp public_message(%Execution{}), do: "Signal processing failed"
  defp public_message(%Routing{}), do: "Signal routing failed"
  defp public_message(%Timeout{}), do: "Signal processing timed out"
  defp public_message(%Internal{}), do: "Internal error"
  defp public_message(error), do: Exception.message(error)

  defp retryable_from_details?(details) do
    details = normalize_details(details)

    Map.get(details, :retryable?) == true or
      retryable_reason?(Map.get(details, :reason)) or
      retryable_reason?(Map.get(details, :error))
  end

  defp retryable_reason?(%TimeoutError{}), do: true
  defp retryable_reason?(%DispatchError{details: details}), do: retryable_from_details?(details)

  defp retryable_reason?(%ExecutionFailureError{details: details}),
    do: retryable_from_details?(details)

  defp retryable_reason?(%InternalError{details: details}), do: retryable_from_details?(details)

  defp retryable_reason?(%Internal.UnknownError{details: details}),
    do: retryable_from_details?(details)

  defp retryable_reason?(%{errors: errors}) when is_list(errors) and is_integer(length(errors)),
    do: Enum.any?(errors, &retryable?/1)

  defp retryable_reason?(:timeout), do: true
  defp retryable_reason?(:econnrefused), do: true
  defp retryable_reason?(:closed), do: true
  defp retryable_reason?(:closed_remotely), do: true
  defp retryable_reason?(:retry_failed), do: true
  defp retryable_reason?(:queue_full), do: true
  defp retryable_reason?(:subscription_not_available), do: true
  defp retryable_reason?(:circuit_open), do: true
  defp retryable_reason?({:http_status, status}) when status in [408, 425, 429], do: true

  defp retryable_reason?({:http_status, status}) when status >= 500 and status <= 599,
    do: true

  defp retryable_reason?({:status_error, status, _body}) when status in [408, 425, 429], do: true

  defp retryable_reason?({:status_error, status, _body}) when status >= 500 and status <= 599,
    do: true

  defp retryable_reason?({:failed_connect, _}), do: true
  defp retryable_reason?({:transport, reason}), do: retryable_reason?(reason)
  defp retryable_reason?({:exception, _}), do: false
  defp retryable_reason?(_reason), do: false

  defp transport_details(details) do
    case Sanitizer.sanitize(details, :transport) do
      %{} = sanitized -> sanitized
      other -> %{"value" => other}
    end
  end

  defp normalize_details(details) when is_list(details) do
    if Keyword.keyword?(details), do: Map.new(details), else: %{value: details}
  end

  defp normalize_details(%{} = details), do: details
  defp normalize_details(nil), do: %{}
  defp normalize_details(details), do: %{value: details}
end
