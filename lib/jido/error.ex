defmodule Jido.Error do
  @moduledoc """
  Unified error handling for the Jido ecosystem using Splode.

  ## Error Types

  Six consolidated error types cover all failure scenarios:

  | Error | Use Case |
  |-------|----------|
  | `ValidationError` | Invalid inputs, actions, sensors, configs |
  | `ExecutionError` | Runtime failures during execution or planning |
  | `RoutingError` | Signal routing and dispatch failures |
  | `TimeoutError` | Operation timeouts |
  | `CompensationError` | Saga compensation failures |
  | `InternalError` | Unexpected system failures |

  ## Usage

      # Validation failures (with optional kind)
      Jido.Error.validation_error("Invalid email", kind: :input, field: :email)
      Jido.Error.validation_error("Unknown action", kind: :action, action: MyAction)

      # Execution failures (with optional phase)
      Jido.Error.execution_error("Action failed", phase: :run)
      Jido.Error.execution_error("Planning failed", phase: :planning)

      # Routing/dispatch failures
      Jido.Error.routing_error("No handler", target: "user.created")

      # Timeouts
      Jido.Error.timeout_error("Timed out", timeout: 5000)

      # Internal errors
      Jido.Error.internal_error("Unexpected failure")

  ## Splode Error Classes

  Errors are classified for aggregation (in order of precedence):
  - `:invalid` - Validation failures
  - `:execution` - Runtime failures
  - `:routing` - Routing/dispatch failures
  - `:timeout` - Timeouts
  - `:internal` - Unexpected failures
  """

  # Splode error classes (internal - do not use directly)

  defmodule Invalid do
    @moduledoc false
    use Splode.ErrorClass, class: :invalid
  end

  defmodule Execution do
    @moduledoc false
    use Splode.ErrorClass, class: :execution
  end

  defmodule Routing do
    @moduledoc false
    use Splode.ErrorClass, class: :routing
  end

  defmodule Timeout do
    @moduledoc false
    use Splode.ErrorClass, class: :timeout
  end

  defmodule Internal do
    @moduledoc false
    use Splode.ErrorClass, class: :internal

    defmodule UnknownError do
      @moduledoc false
      use Splode.Error, class: :internal, fields: [:message, :details, :error]

      @impl true
      def exception(opts) do
        opts = if is_map(opts), do: Map.to_list(opts), else: opts

        message =
          opts
          |> Keyword.get(:message)
          |> Kernel.||(unknown_message(opts[:error]))

        opts
        |> Keyword.put(:message, message)
        |> Keyword.put_new(:details, %{})
        |> super()
      end

      defp unknown_message(error) when is_binary(error), do: error
      defp unknown_message(nil), do: "Unknown error"
      defp unknown_message(error), do: inspect(error)
    end
  end

  use Splode,
    error_classes: [
      invalid: Invalid,
      execution: Execution,
      routing: Routing,
      timeout: Timeout,
      internal: Internal
    ],
    unknown_error: Internal.UnknownError

  # ============================================================================
  # Error Structs
  # ============================================================================

  defmodule ValidationError do
    @moduledoc """
    Error for validation failures.

    Covers invalid inputs, actions, sensors, and configurations.

    ## Fields

    - `message` - Human-readable error message
    - `kind` - Category: `:input`, `:action`, `:sensor`, `:config`
    - `subject` - The invalid value (field name, action module, etc.)
    - `details` - Additional context
    """
    use Splode.Error,
      class: :invalid,
      fields: [:message, :kind, :subject, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            kind: :input | :action | :sensor | :config | nil,
            subject: any(),
            details: map()
          }

    @impl true
    def exception(opts) do
      opts = if is_map(opts), do: Map.to_list(opts), else: opts

      opts
      |> Keyword.put_new(:message, "Validation failed")
      |> Keyword.put_new(:details, %{})
      |> super()
    end
  end

  defmodule ExecutionError do
    @moduledoc """
    Error for runtime execution failures.

    Covers action execution and planning failures.

    ## Fields

    - `message` - Human-readable error message
    - `phase` - Where failure occurred: `:execution`, `:planning`
    - `details` - Additional context
    """
    use Splode.Error,
      class: :execution,
      fields: [:message, :phase, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            phase: :execution | :planning | nil,
            details: map()
          }

    @impl true
    def exception(opts) do
      opts = if is_map(opts), do: Map.to_list(opts), else: opts

      opts
      |> Keyword.put_new(:message, "Execution failed")
      |> Keyword.put_new(:phase, :execution)
      |> Keyword.put_new(:details, %{})
      |> super()
    end
  end

  defmodule RoutingError do
    @moduledoc """
    Error for signal routing and dispatch failures.

    ## Fields

    - `message` - Human-readable error message
    - `target` - The intended routing target
    - `details` - Additional context
    """
    use Splode.Error,
      class: :routing,
      fields: [:message, :target, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            target: any(),
            details: map()
          }

    @impl true
    def exception(opts) do
      opts = if is_map(opts), do: Map.to_list(opts), else: opts

      opts
      |> Keyword.put_new(:message, "Routing failed")
      |> Keyword.put_new(:details, %{})
      |> super()
    end
  end

  defmodule TimeoutError do
    @moduledoc """
    Error for operation timeouts.

    ## Fields

    - `message` - Human-readable error message
    - `timeout` - The timeout value in milliseconds
    - `details` - Additional context
    """
    use Splode.Error,
      class: :timeout,
      fields: [:message, :timeout, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            timeout: non_neg_integer() | nil,
            details: map()
          }

    @impl true
    def exception(opts) do
      opts = if is_map(opts), do: Map.to_list(opts), else: opts

      opts
      |> Keyword.put_new(:message, "Operation timed out")
      |> Keyword.put_new(:details, %{})
      |> super()
    end
  end

  defmodule CompensationError do
    @moduledoc """
    Error for saga compensation failures.

    ## Fields

    - `message` - Human-readable error message
    - `original_error` - The error that triggered compensation
    - `compensated` - Whether compensation succeeded
    - `result` - Result from successful compensation
    - `details` - Additional context
    """
    use Splode.Error,
      class: :execution,
      fields: [:message, :original_error, :compensated, :result, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            original_error: any(),
            compensated: boolean(),
            result: any(),
            details: map()
          }

    @impl true
    def exception(opts) do
      opts = if is_map(opts), do: Map.to_list(opts), else: opts

      opts
      |> Keyword.put_new(:message, "Compensation error")
      |> Keyword.put_new(:compensated, false)
      |> Keyword.put_new(:details, %{})
      |> super()
    end
  end

  defmodule InternalError do
    @moduledoc """
    Error for unexpected internal failures.

    ## Fields

    - `message` - Human-readable error message
    - `details` - Additional context
    """
    use Splode.Error, class: :internal, fields: [:message, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            details: map()
          }

    @impl true
    def exception(opts) do
      opts = if is_map(opts), do: Map.to_list(opts), else: opts

      opts
      |> Keyword.put_new(:message, "Internal error")
      |> Keyword.put_new(:details, %{})
      |> super()
    end
  end

  # ============================================================================
  # Error Constructors
  # ============================================================================

  @doc """
  Creates a validation error.

  ## Options

  - `:kind` - Category: `:input`, `:action`, `:sensor`, `:config`
  - `:subject` - The invalid value
  - `:field` - Alias for `:subject` (for input validation)
  - `:action` - Alias for `:subject` with `kind: :action`
  - `:sensor` - Alias for `:subject` with `kind: :sensor`
  - `:details` - Additional context map

  ## Examples

      validation_error("Invalid email", field: :email)
      validation_error("Unknown action", kind: :action, subject: MyAction)
  """
  @spec validation_error(String.t(), keyword() | map()) :: ValidationError.t()
  def validation_error(message, opts \\ []) do
    opts = if is_map(opts), do: Map.to_list(opts), else: opts

    # Infer kind and subject from convenience keys
    {kind, subject} =
      cond do
        opts[:action] -> {:action, opts[:action]}
        opts[:sensor] -> {:sensor, opts[:sensor]}
        opts[:field] -> {:input, opts[:field]}
        true -> {opts[:kind], opts[:subject]}
      end

    ValidationError.exception(
      message: message,
      kind: kind,
      subject: subject,
      details: Keyword.get(opts, :details, %{})
    )
  end

  @doc """
  Creates an execution error.

  ## Options

  - `:phase` - Where failure occurred: `:execution`, `:planning`
  - `:details` - Additional context map
  """
  @spec execution_error(String.t(), keyword() | map()) :: ExecutionError.t()
  def execution_error(message, opts \\ []) do
    opts = if is_map(opts), do: Map.to_list(opts), else: opts

    ExecutionError.exception(
      message: message,
      phase: Keyword.get(opts, :phase, :execution),
      details: Keyword.get(opts, :details, %{})
    )
  end

  @doc """
  Creates a routing error.

  ## Options

  - `:target` - The intended routing target
  - `:details` - Additional context map
  """
  @spec routing_error(String.t(), keyword() | map()) :: RoutingError.t()
  def routing_error(message, opts \\ []) do
    opts = if is_map(opts), do: Map.to_list(opts), else: opts

    RoutingError.exception(
      message: message,
      target: Keyword.get(opts, :target),
      details: Keyword.get(opts, :details, %{})
    )
  end

  @doc """
  Creates a timeout error.

  ## Options

  - `:timeout` - The timeout value in milliseconds
  - `:details` - Additional context map
  """
  @spec timeout_error(String.t(), keyword() | map()) :: TimeoutError.t()
  def timeout_error(message, opts \\ []) do
    opts = if is_map(opts), do: Map.to_list(opts), else: opts

    TimeoutError.exception(
      message: message,
      timeout: Keyword.get(opts, :timeout),
      details: Keyword.get(opts, :details, %{})
    )
  end

  @doc """
  Creates a compensation error.

  ## Options

  - `:original_error` - The error that triggered compensation
  - `:compensated` - Whether compensation succeeded (default: false)
  - `:result` - Result from successful compensation
  - `:details` - Additional context map
  """
  @spec compensation_error(String.t(), keyword() | map()) :: CompensationError.t()
  def compensation_error(message, opts \\ []) do
    opts = if is_map(opts), do: Map.to_list(opts), else: opts

    CompensationError.exception(
      message: message,
      original_error: Keyword.get(opts, :original_error),
      compensated: Keyword.get(opts, :compensated, false),
      result: Keyword.get(opts, :result),
      details: Keyword.get(opts, :details, %{})
    )
  end

  @doc """
  Creates an internal error.

  ## Options

  - `:details` - Additional context map
  """
  @spec internal_error(String.t(), keyword() | map()) :: InternalError.t()
  def internal_error(message, opts \\ []) do
    opts = if is_map(opts), do: Map.to_list(opts), else: opts

    InternalError.exception(
      message: message,
      details: Keyword.get(opts, :details, %{})
    )
  end

  # ============================================================================
  # Utilities
  # ============================================================================

  @doc """
  Converts an error struct to a normalized map.

  Returns a map with `:type`, `:message`, `:details`, and `:stacktrace` keys.
  """
  @spec to_map(any()) :: map()
  def to_map(error) do
    case error do
      %{message: message} = err ->
        %{
          type: unified_type(err),
          message: message,
          details: Map.get(err, :details, %{}),
          stacktrace: capture_stacktrace()
        }

      _ ->
        %{
          type: :internal,
          message: inspect(error),
          details: %{},
          stacktrace: capture_stacktrace()
        }
    end
  end

  @doc """
  Extracts the message string from a nested error structure.
  """
  @spec extract_message(any()) :: String.t()
  def extract_message(error) do
    case error do
      %{message: %{message: inner}} when is_binary(inner) -> inner
      %{message: nil} -> ""
      %{message: msg} when is_binary(msg) -> msg
      %{message: msg} when is_struct(msg) -> Map.get(msg, :message, inspect(msg))
      _ -> inspect(error)
    end
  end

  @doc """
  Formats a NimbleOptions configuration error.
  """
  @spec format_nimble_config_error(any(), String.t(), module()) :: String.t()
  def format_nimble_config_error(
        %NimbleOptions.ValidationError{keys_path: [], message: message},
        module_type,
        module
      ) do
    "Invalid configuration for #{module_type} (#{module}): #{message}"
  end

  def format_nimble_config_error(
        %NimbleOptions.ValidationError{keys_path: keys_path, message: message},
        module_type,
        module
      ) do
    "Invalid configuration for #{module_type} (#{module}) at #{inspect(keys_path)}: #{message}"
  end

  def format_nimble_config_error(error, _module_type, _module) when is_binary(error), do: error
  def format_nimble_config_error(error, _module_type, _module), do: inspect(error)

  @doc """
  Formats a NimbleOptions validation error for parameters.
  """
  @spec format_nimble_validation_error(any(), String.t(), module()) :: String.t()
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

  @doc false
  def capture_stacktrace do
    {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)
    Enum.drop(stacktrace, 2)
  end

  # Maps error structs to unified type atoms
  defp unified_type(%ValidationError{kind: :action}), do: :invalid_action
  defp unified_type(%ValidationError{kind: :sensor}), do: :invalid_sensor
  defp unified_type(%ValidationError{kind: :config}), do: :config_error
  defp unified_type(%ValidationError{}), do: :validation_error
  defp unified_type(%ExecutionError{phase: :planning}), do: :planning_error
  defp unified_type(%ExecutionError{}), do: :execution_error
  defp unified_type(%RoutingError{}), do: :routing_error
  defp unified_type(%TimeoutError{}), do: :timeout
  defp unified_type(%CompensationError{}), do: :compensation_error
  defp unified_type(%InternalError{}), do: :internal
  defp unified_type(%Internal.UnknownError{}), do: :internal

  # Cross-package error mapping (jido_action, jido_signal)
  defp unified_type(%Jido.Action.Error.InvalidInputError{}), do: :validation_error
  defp unified_type(%Jido.Action.Error.ExecutionFailureError{}), do: :execution_error
  defp unified_type(%Jido.Action.Error.TimeoutError{}), do: :timeout
  defp unified_type(%Jido.Action.Error.ConfigurationError{}), do: :config_error
  defp unified_type(%Jido.Action.Error.InternalError{}), do: :internal

  defp unified_type(%Jido.Signal.Error.InvalidInputError{}), do: :validation_error
  defp unified_type(%Jido.Signal.Error.ExecutionFailureError{}), do: :execution_error
  defp unified_type(%Jido.Signal.Error.RoutingError{}), do: :routing_error
  defp unified_type(%Jido.Signal.Error.TimeoutError{}), do: :timeout
  defp unified_type(%Jido.Signal.Error.DispatchError{}), do: :routing_error
  defp unified_type(%Jido.Signal.Error.InternalError{}), do: :internal

  defp unified_type(_), do: :internal
end
