defmodule Jido.Error do
  @moduledoc """
  Unified error handling across the Jido ecosystem using Splode.

  This module provides cohesive error management for all Jido packages 
  (jido, jido_action, jido_signal), enabling seamless error composition, 
  classification, and handling across package boundaries.

  ## Cross-Package Error Integration

  Splode enables consistent error handling between:
  - **Jido.Error** - Core agent framework errors
  - **Jido.Action.Error** - Action execution errors 
  - **Jido.Signal.Error** - Signal processing errors

  All errors are automatically mapped to unified types for consistent handling.

  ## Error Classes

  Errors are organized into the following classes, in order of precedence:

  - `:invalid` - Input validation, bad requests, and invalid configurations
  - `:execution` - Runtime execution errors and action failures
  - `:planning` - Action planning and workflow errors
  - `:routing` - Agent routing and dispatch errors
  - `:timeout` - Action and process timeouts
  - `:internal` - Unexpected internal errors and system failures

  When multiple errors are aggregated, the class of the highest precedence error
  determines the overall error class.

  ## Usage

  Use this module to create and handle errors consistently:

      # Create a specific error
      {:error, error} = Jido.Error.validation_error("Invalid parameters", field: :user_id)

      # Create timeout error
      {:error, timeout} = Jido.Error.timeout_error("Action timed out after 30s", timeout: 30000)

      # Convert any value to a proper error
      {:error, normalized} = Jido.Error.to_error("Something went wrong")
  """

  # Error class modules for Splode
  defmodule Invalid do
    @moduledoc "Invalid input error class"
    use Splode.ErrorClass, class: :invalid
  end

  defmodule Execution do
    @moduledoc "Execution error class"
    use Splode.ErrorClass, class: :execution
  end

  defmodule Planning do
    @moduledoc "Planning error class"
    use Splode.ErrorClass, class: :planning
  end

  defmodule Routing do
    @moduledoc "Routing error class"
    use Splode.ErrorClass, class: :routing
  end

  defmodule Timeout do
    @moduledoc "Timeout error class"
    use Splode.ErrorClass, class: :timeout
  end

  defmodule Internal do
    @moduledoc "Internal error class"
    use Splode.ErrorClass, class: :internal

    defmodule UnknownError do
      @moduledoc "Unknown internal error"
      defexception [:message, :details]

      @impl true
      def exception(opts) do
        %__MODULE__{
          message: Keyword.get(opts, :message, "Unknown error"),
          details: Keyword.get(opts, :details, %{})
        }
      end
    end
  end

  use Splode,
    error_classes: [
      invalid: Invalid,
      execution: Execution,
      planning: Planning,
      routing: Routing,
      timeout: Timeout,
      internal: Internal
    ],
    unknown_error: Internal.UnknownError

  # Define specific error structs inline
  defmodule InvalidInputError do
    @moduledoc "Error for invalid input parameters"
    defexception [:message, :field, :value, :details]

    @impl true
    def exception(opts) do
      message = Keyword.get(opts, :message, "Invalid input")

      %__MODULE__{
        message: message,
        field: Keyword.get(opts, :field),
        value: Keyword.get(opts, :value),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule InvalidActionError do
    @moduledoc "Error for invalid action definitions or usage"
    defexception [:message, :action, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Invalid action"),
        action: Keyword.get(opts, :action),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule InvalidSensorError do
    @moduledoc "Error for invalid sensor definitions or usage"
    defexception [:message, :sensor, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Invalid sensor"),
        sensor: Keyword.get(opts, :sensor),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule ExecutionFailureError do
    @moduledoc "Error for runtime execution failures"
    defexception [:message, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Execution failed"),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule PlanningError do
    @moduledoc "Error for action planning failures"
    defexception [:message, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Planning failed"),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule RoutingError do
    @moduledoc "Error for agent routing failures"
    defexception [:message, :target, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Routing failed"),
        target: Keyword.get(opts, :target),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule DispatchError do
    @moduledoc "Error for signal dispatch failures"
    defexception [:message, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Dispatch failed"),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule TimeoutError do
    @moduledoc "Error for action and process timeouts"
    defexception [:message, :timeout, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Operation timed out"),
        timeout: Keyword.get(opts, :timeout),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule CompensationError do
    @moduledoc "Error for compensation failures"
    defexception [
      :message,
      :original_error,
      :compensated,
      :compensation_result,
      :compensation_error,
      :details
    ]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Compensation error"),
        original_error: Keyword.get(opts, :original_error),
        compensated: Keyword.get(opts, :compensated, false),
        compensation_result: Keyword.get(opts, :compensation_result),
        compensation_error: Keyword.get(opts, :compensation_error),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule ConfigurationError do
    @moduledoc "Error for configuration issues"
    defexception [:message, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Configuration error"),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule InternalError do
    @moduledoc "Error for unexpected internal failures"
    defexception [:message, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Internal error"),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  @doc """
  Creates a validation error for invalid input parameters.
  """
  def validation_error(message, details \\ %{}) do
    InvalidInputError.exception(
      message: message,
      field: details[:field],
      value: details[:value],
      details: details
    )
  end

  @doc """
  Creates an invalid action error.
  """
  def invalid_action(message, details \\ %{}) do
    InvalidActionError.exception(
      message: message,
      action: details[:action],
      details: details
    )
  end

  @doc """
  Creates an invalid sensor error.
  """
  def invalid_sensor(message, details \\ %{}) do
    InvalidSensorError.exception(
      message: message,
      sensor: details[:sensor],
      details: details
    )
  end

  @doc """
  Creates a bad request error (alias for validation_error for compatibility).
  """
  def bad_request(message, details \\ %{}) do
    validation_error(message, details)
  end

  @doc """
  Creates an execution error for runtime failures.
  """
  def execution_error(message, details \\ %{}) do
    ExecutionFailureError.exception(
      message: message,
      details: details
    )
  end

  @doc """
  Creates a planning error for action planning failures.
  """
  def planning_error(message, details \\ %{}) do
    PlanningError.exception(
      message: message,
      details: details
    )
  end

  @doc """
  Creates an action error (alias for execution_error for compatibility).
  """
  def action_error(message, details \\ %{}) do
    execution_error(message, details)
  end

  @doc """
  Creates a routing error for agent routing failures.
  """
  def routing_error(message, details \\ %{}) do
    RoutingError.exception(
      message: message,
      target: details[:target],
      details: details
    )
  end

  @doc """
  Creates a dispatch error for signal dispatch failures.
  """
  def dispatch_error(message, details \\ %{}) do
    DispatchError.exception(
      message: message,
      details: details
    )
  end

  @doc """
  Creates a timeout error.
  """
  def timeout(message, details \\ %{}) do
    TimeoutError.exception(
      message: message,
      timeout: details[:timeout],
      details: details
    )
  end

  @doc """
  Creates a timeout error (alias for timeout for compatibility).
  """
  def timeout_error(message, details \\ %{}) do
    timeout(message, details)
  end

  @doc """
  Creates an invalid async ref error (maps to internal error).
  """
  def invalid_async_ref(message, details \\ %{}) do
    InternalError.exception(
      message: message,
      details: details
    )
  end

  @doc """
  Creates a compensation error with details about the original error and compensation attempt.

  ## Parameters

  - `original_error`: The error that triggered compensation
  - `details`: Map containing:
    - `:compensated` - Boolean indicating if compensation succeeded
    - `:compensation_result` - Result from successful compensation
    - `:compensation_error` - Error from failed compensation

  ## Examples

      iex> original_error = Jido.Error.execution_error("Failed to process payment")
      iex> Jido.Error.compensation_error(original_error, %{
      ...>   compensated: true,
      ...>   compensation_result: %{refund_id: "ref_123"}
      ...> })
  """
  def compensation_error(original_error, details \\ %{}) do
    # Strip the error type prefix from the message if it exists
    original_message = extract_message(original_error)

    message =
      if details[:compensated],
        do: "Compensation completed for: #{original_message}",
        else: "Compensation failed for: #{original_message}"

    CompensationError.exception(
      message: message,
      original_error: original_error,
      compensated: details[:compensated],
      compensation_result: details[:compensation_result],
      compensation_error: details[:compensation_error],
      details: details
    )
  end

  @doc """
  Creates a configuration error.
  """
  def config_error(message, details \\ %{}) do
    ConfigurationError.exception(
      message: message,
      details: details
    )
  end

  @doc """
  Creates an internal server error.
  """
  def internal_server_error(message, details \\ %{}) do
    InternalError.exception(
      message: message,
      details: details
    )
  end

  @doc """
  Creates an internal error.
  """
  def internal_error(message, details \\ %{}) do
    internal_server_error(message, details)
  end

  @doc """
  Formats a NimbleOptions configuration error for display.
  Used when configuration validation fails during compilation.
  """
  @spec format_nimble_config_error(
          NimbleOptions.ValidationError.t() | any(),
          String.t(),
          module()
        ) ::
          String.t()
  def format_nimble_config_error(
        %NimbleOptions.ValidationError{keys_path: [], message: message},
        module_type,
        module
      ) do
    "Invalid configuration given to use Jido.#{module_type} (#{module}): #{message}"
  end

  def format_nimble_config_error(
        %NimbleOptions.ValidationError{keys_path: keys_path, message: message},
        module_type,
        module
      ) do
    "Invalid configuration given to use Jido.#{module_type} (#{module}) for key #{inspect(keys_path)}: #{message}"
  end

  def format_nimble_config_error(error, _module_type, _module) when is_binary(error), do: error
  def format_nimble_config_error(error, _module_type, _module), do: inspect(error)

  @doc """
  Formats a NimbleOptions validation error for parameter validation.
  Used when validating runtime parameters.
  """
  @spec format_nimble_validation_error(
          NimbleOptions.ValidationError.t() | any(),
          String.t(),
          module()
        ) ::
          String.t()
  def format_nimble_validation_error(
        %NimbleOptions.ValidationError{keys_path: [], message: message},
        module_type,
        module
      ) do
    "Invalid parameters for #{module_type} (#{module}): #{message}"
  end

  def format_nimble_validation_error(
        %NimbleOptions.ValidationError{keys_path: keys_path, message: message},
        module_type,
        module
      ) do
    "Invalid parameters for #{module_type} (#{module}) at #{inspect(keys_path)}: #{message}"
  end

  def format_nimble_validation_error(error, _module_type, _module) when is_binary(error),
    do: error

  def format_nimble_validation_error(error, _module_type, _module), do: inspect(error)

  # Compatibility functions for unified error handling across Jido packages
  # These maintain the existing API while using Splode-based error structures

  @doc """
  Creates new error structs using the unified error system.
  Maps error types to Splode-based errors for cohesive cross-package handling.
  """
  def new(type, message, details \\ nil, stacktrace \\ nil)

  def new(:invalid_action, message, details, _stacktrace) do
    invalid_action(message, details || %{})
  end

  def new(:invalid_sensor, message, details, _stacktrace) do
    invalid_sensor(message, details || %{})
  end

  def new(:bad_request, message, details, _stacktrace) do
    bad_request(message, details || %{})
  end

  def new(:validation_error, message, details, _stacktrace) do
    validation_error(message, details || %{})
  end

  def new(:config_error, message, details, _stacktrace) do
    config_error(message, details || %{})
  end

  def new(:execution_error, message, details, _stacktrace) do
    execution_error(message, details || %{})
  end

  def new(:planning_error, message, details, _stacktrace) do
    planning_error(message, details || %{})
  end

  def new(:action_error, message, details, _stacktrace) do
    action_error(message, details || %{})
  end

  def new(:internal_server_error, message, details, _stacktrace) do
    internal_server_error(message, details || %{})
  end

  def new(:timeout, message, details, _stacktrace) do
    timeout(message, details || %{})
  end

  def new(:invalid_async_ref, message, details, _stacktrace) do
    invalid_async_ref(message, details || %{})
  end

  def new(:compensation_error, _message, details, _stacktrace) do
    # For compensation errors, we need to handle the original error differently
    original_error = details[:original_error] || execution_error("Unknown error")
    compensation_error(original_error, details || %{})
  end

  def new(:routing_error, message, details, _stacktrace) do
    routing_error(message, details || %{})
  end

  def new(:dispatch_error, message, details, _stacktrace) do
    dispatch_error(message, details || %{})
  end

  def new(unknown_type, message, details, _stacktrace) do
    internal_error("Unknown error type: #{unknown_type} - #{message}", details || %{})
  end

  @doc """
  Converts error structs to maps using the unified error system.
  Provides consistent error representation across Jido packages.
  """
  def to_map(error) do
    case error do
      # Handle Jido.Action.Error and Jido.Signal.Error structs
      %{__struct__: struct_name, type: type, message: message} ->
        case to_string(struct_name) do
          "Elixir.Jido.Action.Error" <> _ ->
            # Extract inner error if message is an error struct
            inner_error = if is_struct(message), do: message, else: nil
            actual_type = if inner_error, do: determine_unified_type(inner_error), else: type
            actual_message = if inner_error, do: inner_error.message, else: message
            details = if inner_error, do: Map.get(inner_error, :details, %{}), else: %{}

            %{
              type: actual_type,
              message: actual_message,
              details: details,
              stacktrace: capture_stacktrace()
            }

          "Elixir.Jido.Signal.Error" <> _ ->
            # Handle Jido.Signal.Error structs directly
            %{
              type: type,
              message: message,
              details: Map.get(error, :details, %{}),
              stacktrace: capture_stacktrace()
            }

          _ ->
            # Handle other structs with message field
            details = Map.get(error, :details, %{})

            %{
              type: determine_unified_type(error),
              message: message,
              details: details,
              stacktrace: capture_stacktrace()
            }
        end

      %{message: message} = error_struct ->
        # Convert splode error to unified format
        details = Map.get(error_struct, :details, %{})

        %{
          type: determine_unified_type(error_struct),
          message: message,
          details: details,
          stacktrace: capture_stacktrace()
        }

      _ ->
        %{
          type: :internal_server_error,
          message: inspect(error),
          details: %{},
          stacktrace: capture_stacktrace()
        }
    end
  end

  @doc """
  Extracts the actual error message string from a nested error structure.

  Handles the common pattern where Splode wraps errors with nested :message fields.

  ## Examples

      iex> error = %{message: %{message: "Exec failed"}}
      iex> Jido.Error.extract_message(error)
      "Exec failed"
      
      iex> error = %{message: "Direct message"}
      iex> Jido.Error.extract_message(error)
      "Direct message"
  """
  def extract_message(error) do
    case error do
      %{message: %{message: inner_message}} when is_binary(inner_message) ->
        inner_message

      %{message: nil} ->
        ""

      %{message: message} when is_binary(message) ->
        message

      %{message: message} when is_struct(message) ->
        if Map.has_key?(message, :message) and is_binary(message.message) do
          message.message
        else
          inspect(message)
        end

      _ ->
        inspect(error)
    end
  end

  @doc """
  Captures the current stacktrace for error reporting.
  """
  def capture_stacktrace do
    {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)
    Enum.drop(stacktrace, 2)
  end

  # Helper to map Splode error structs to unified error types across Jido packages
  defp determine_unified_type(%InvalidInputError{}), do: :validation_error
  defp determine_unified_type(%InvalidActionError{}), do: :invalid_action
  defp determine_unified_type(%InvalidSensorError{}), do: :invalid_sensor
  defp determine_unified_type(%ExecutionFailureError{}), do: :execution_error
  defp determine_unified_type(%PlanningError{}), do: :planning_error
  defp determine_unified_type(%RoutingError{}), do: :routing_error
  defp determine_unified_type(%DispatchError{}), do: :dispatch_error
  defp determine_unified_type(%TimeoutError{}), do: :timeout
  defp determine_unified_type(%CompensationError{}), do: :compensation_error
  defp determine_unified_type(%ConfigurationError{}), do: :config_error
  defp determine_unified_type(%InternalError{}), do: :internal_server_error
  defp determine_unified_type(%Internal.UnknownError{}), do: :internal_server_error

  # Map Jido.Action.Error types to unified types for cohesive cross-package handling
  defp determine_unified_type(%Jido.Action.Error.InvalidInputError{}), do: :validation_error
  defp determine_unified_type(%Jido.Action.Error.ExecutionFailureError{}), do: :execution_error
  defp determine_unified_type(%Jido.Action.Error.TimeoutError{}), do: :timeout
  defp determine_unified_type(%Jido.Action.Error.ConfigurationError{}), do: :config_error
  defp determine_unified_type(%Jido.Action.Error.InternalError{}), do: :internal_server_error

  # Map Jido.Signal.Error types to unified types for cohesive cross-package handling
  defp determine_unified_type(%Jido.Signal.Error.InvalidInputError{}), do: :validation_error
  defp determine_unified_type(%Jido.Signal.Error.ExecutionFailureError{}), do: :execution_error
  defp determine_unified_type(%Jido.Signal.Error.RoutingError{}), do: :routing_error
  defp determine_unified_type(%Jido.Signal.Error.TimeoutError{}), do: :timeout
  defp determine_unified_type(%Jido.Signal.Error.DispatchError{}), do: :dispatch_error
  defp determine_unified_type(%Jido.Signal.Error.InternalError{}), do: :internal_server_error

  defp determine_unified_type(_), do: :internal_server_error
end
