defmodule Jido.Error do
  @moduledoc """
  Defines error structures and helper functions for Jido

  This module provides a standardized way to create and handle errors within the Jido system.
  It offers a set of predefined error types and functions to create, manipulate, and convert
  error structures consistently across the application.

  > Why not use Exceptions?
  >
  > Jido is designed to be a functional system, strictly adhering to the use of result tuples.
  > This approach provides several benefits:
  >
  > 1. Consistent error handling: By using `{:ok, result}` or `{:error, reason}` tuples,
  >    we ensure a uniform way of handling success and failure cases throughout the system.
  >
  > 2. Composability: Monadic workflows can be easily chained together, allowing for
  >    cleaner and more maintainable code.
  >
  > 3. Explicit error paths: The use of result tuples makes error cases explicit,
  >    reducing the likelihood of unhandled errors.
  >
  > 4. No silent failures: Unlike exceptions, which can be silently caught and ignored,
  >    result tuples require explicit handling of both success and error cases.
  >
  > 5. Better testability: Monadic workflows are easier to test, as both success and
  >    error paths can be explicitly verified.
  >
  > By using this approach instead of exceptions, we gain more control over the flow of our
  > workflows and ensure that errors are handled consistently across the entire system.

  ## Usage

  Use this module to create specific error types when exceptions occur in your Jido workflows.
  This allows for consistent error handling and reporting throughout the system.

  Example:

      defmodule MyWorkflow do
        alias Jido.Error

        def run(params) do
          case validate(params) do
            :ok -> perform_workflow(params)
            {:error, reason} -> Error.validation_error("Invalid parameters")
          end
        end
      end
  """

  @typedoc """
  Defines the possible error types in the Jido system.

  - `:invalid_action`: Used when a action is improperly defined or used.
  - `:invalid_sensor`: Used when a sensor is improperly defined or used.
  - `:bad_request`: Indicates an invalid request from the client.
  - `:validation_error`: Used when input validation fails.
  - `:config_error`: Indicates a configuration issue.
  - `:execution_error`: Used when an error occurs during workflow execution.
  - `:workflow_error`: General workflow-related errors.
  - `:internal_server_error`: Indicates an unexpected internal error.
  - `:timeout`: Used when an workflow exceeds its time limit.
  - `:invalid_async_ref`: Indicates an invalid asynchronous workflow reference.
  - `:compensation_error`: Indicates an error occurred during compensation.
  - `:planning_error`: Used when an error occurs during workflow planning.
  - `:routing_error`: Used when an error occurs during workflow routing.
  """
  @type error_type ::
          :invalid_action
          | :invalid_sensor
          | :bad_request
          | :validation_error
          | :config_error
          | :execution_error
          | :planning_error
          | :workflow_error
          | :internal_server_error
          | :timeout
          | :invalid_async_ref
          | :compensation_error
          | :routing_error

  use TypedStruct

  @typedoc """
  Represents a structured error in the Jido system.

  Fields:
  - `type`: The category of the error (see `t:error_type/0`).
  - `message`: A human-readable description of the error.
  - `details`: Optional map containing additional error context.
  - `stacktrace`: Optional list representing the error's stacktrace.
  """
  typedstruct do
    field(:type, error_type(), enforce: true)
    field(:message, String.t(), enforce: true)
    field(:details, map(), default: %{})
    field(:stacktrace, list(), default: [])
  end

  @doc """
  Creates a new error struct with the given type and message.

  This is a low-level function used by other error creation functions in this module.
  Consider using the specific error creation functions unless you need fine-grained control.

  ## Parameters
  - `type`: The error type (see `t:error_type/0`).
  - `message`: A string describing the error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Examples

      iex> Jido.Error.new(:config_error, "Invalid configuration")
      %Jido.Error{
        type: :config_error,
        message: "Invalid configuration",
        details: nil,
        stacktrace: [...]
      }

      iex> Jido.Error.new(:execution_error, "Workflow failed", %{step: "data_processing"})
      %Jido.Error{
        type: :execution_error,
        message: "Workflow failed",
        details: %{step: "data_processing"},
        stacktrace: [...]
      }
  """
  @spec new(error_type(), String.t(), map() | nil, list() | nil) :: t()
  def new(type, message, details \\ nil, stacktrace \\ nil) do
    %__MODULE__{
      type: type,
      message: message,
      details: details,
      stacktrace: stacktrace || capture_stacktrace()
    }
  end

  @doc """
  Creates a new invalid action error.

  Use this when a action is improperly defined or used within the Jido system.

  ## Parameters
  - `message`: A string describing the error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Error.invalid_action("Action 'MyAction' is missing required callback")
      %Jido.Error{
        type: :invalid_action,
        message: "Action 'MyAction' is missing required callback",
        details: nil,
        stacktrace: [...]
      }
  """
  @spec invalid_action(String.t(), map() | nil, list() | nil) :: t()
  def invalid_action(message, details \\ nil, stacktrace \\ nil) do
    new(:invalid_action, message, details, stacktrace)
  end

  @doc """
  Creates a new invalid sensor error.

  Use this when a sensor is improperly defined or used within the Jido system.

  ## Parameters
  - `message`: A string describing the error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Error.invalid_sensor("Sensor 'MySensor' is missing required callback")
      %Jido.Error{
        type: :invalid_sensor,
        message: "Sensor 'MySensor' is missing required callback",
        details: nil,
        stacktrace: [...]
      }
  """
  @spec invalid_sensor(String.t(), map() | nil, list() | nil) :: t()
  def invalid_sensor(message, details \\ nil, stacktrace \\ nil) do
    new(:invalid_sensor, message, details, stacktrace)
  end

  @doc """
  Creates a new bad request error.

  Use this when the client sends an invalid or malformed request.

  ## Parameters
  - `message`: A string describing the error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Error.bad_request("Missing required parameter 'user_id'")
      %Jido.Error{
        type: :bad_request,
        message: "Missing required parameter 'user_id'",
        details: nil,
        stacktrace: [...]
      }
  """
  @spec bad_request(String.t(), map() | nil, list() | nil) :: t()
  def bad_request(message, details \\ nil, stacktrace \\ nil) do
    new(:bad_request, message, details, stacktrace)
  end

  @doc """
  Creates a new validation error.

  Use this when input validation fails for an workflow.

  ## Parameters
  - `message`: A string describing the validation error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Error.validation_error("Invalid email format", %{field: "email", value: "not-an-email"})
      %Jido.Error{
        type: :validation_error,
        message: "Invalid email format",
        details: %{field: "email", value: "not-an-email"},
        stacktrace: [...]
      }
  """
  @spec validation_error(String.t(), map() | nil, list() | nil) :: t()
  def validation_error(message, details \\ nil, stacktrace \\ nil) do
    new(:validation_error, message, details, stacktrace)
  end

  @doc """
  Creates a new config error.

  Use this when there's an issue with the system or workflow configuration.

  ## Parameters
  - `message`: A string describing the configuration error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Error.config_error("Invalid database connection string")
      %Jido.Error{
        type: :config_error,
        message: "Invalid database connection string",
        details: nil,
        stacktrace: [...]
      }
  """
  @spec config_error(String.t(), map() | nil, list() | nil) :: t()
  def config_error(message, details \\ nil, stacktrace \\ nil) do
    new(:config_error, message, details, stacktrace)
  end

  @doc """
  Creates a new execution error.

  Use this when an error occurs during the execution of an workflow.

  ## Parameters
  - `message`: A string describing the execution error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Error.execution_error("Failed to process data", %{step: "data_transformation"})
      %Jido.Error{
        type: :execution_error,
        message: "Failed to process data",
        details: %{step: "data_transformation"},
        stacktrace: [...]
      }
  """
  @spec execution_error(String.t(), map() | nil, list() | nil) :: t()
  def execution_error(message, details \\ nil, stacktrace \\ nil) do
    new(:execution_error, message, details, stacktrace)
  end

  @doc """
  Creates a new planning error.

  Use this when an error occurs during workflow planning.

  ## Parameters
  - `message`: A string describing the planning error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Error.planning_error("Failed to plan workflow", %{step: "goal_analysis"})
      %Jido.Error{
        type: :planning_error,
        message: "Failed to plan workflow",
        details: %{step: "goal_analysis"},
        stacktrace: [...]
      }
  """
  @spec planning_error(String.t(), map() | nil, list() | nil) :: t()
  def planning_error(message, details \\ nil, stacktrace \\ nil) do
    new(:planning_error, message, details, stacktrace)
  end

  @doc """
  Creates a new workflow error.

  Use this for general workflow-related errors that don't fit into other categories.

  ## Parameters
  - `message`: A string describing the workflow error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Error.workflow_error("Workflow 'ProcessOrder' failed", %{order_id: 12345})
      %Jido.Error{
        type: :workflow_error,
        message: "Workflow 'ProcessOrder' failed",
        details: %{order_id: 12345},
        stacktrace: [...]
      }
  """
  @spec workflow_error(String.t(), map() | nil, list() | nil) :: t()
  def workflow_error(message, details \\ nil, stacktrace \\ nil) do
    new(:workflow_error, message, details, stacktrace)
  end

  @doc """
  Creates a new internal server error.

  Use this for unexpected errors that occur within the system.

  ## Parameters
  - `message`: A string describing the internal server error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Error.internal_server_error("Unexpected error in data processing")
      %Jido.Error{
        type: :internal_server_error,
        message: "Unexpected error in data processing",
        details: nil,
        stacktrace: [...]
      }
  """
  @spec internal_server_error(String.t(), map() | nil, list() | nil) :: t()
  def internal_server_error(message, details \\ nil, stacktrace \\ nil) do
    new(:internal_server_error, message, details, stacktrace)
  end

  @doc """
  Creates a new timeout error.

  Use this when an workflow exceeds its allocated time limit.

  ## Parameters
  - `message`: A string describing the timeout error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Error.timeout("Workflow timed out after 30 seconds", %{workflow: "FetchUserData"})
      %Jido.Error{
        type: :timeout,
        message: "Workflow timed out after 30 seconds",
        details: %{workflow: "FetchUserData"},
        stacktrace: [...]
      }
  """
  @spec timeout(String.t(), map() | nil, list() | nil) :: t()
  def timeout(message, details \\ nil, stacktrace \\ nil) do
    new(:timeout, message, details, stacktrace)
  end

  @doc """
  Creates a new invalid async ref error.

  Use this when an invalid reference to an asynchronous workflow is encountered.

  ## Parameters
  - `message`: A string describing the invalid async ref error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Error.invalid_async_ref("Invalid or expired async workflow reference")
      %Jido.Error{
        type: :invalid_async_ref,
        message: "Invalid or expired async workflow reference",
        details: nil,
        stacktrace: [...]
      }
  """
  @spec invalid_async_ref(String.t(), map() | nil, list() | nil) :: t()
  def invalid_async_ref(message, details \\ nil, stacktrace \\ nil) do
    new(:invalid_async_ref, message, details, stacktrace)
  end

  @doc """
  Creates a new routing error.

  Use this when an error occurs during workflow routing.

  ## Parameters
  - `message`: A string describing the routing error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Error.routing_error("Invalid route configuration", %{route: "user_workflow"})
      %Jido.Error{
        type: :routing_error,
        message: "Invalid route configuration",
        details: %{route: "user_workflow"},
        stacktrace: [...]
      }
  """
  @spec routing_error(String.t(), map() | nil, list() | nil) :: t()
  def routing_error(message, details \\ nil, stacktrace \\ nil) do
    new(:routing_error, message, details, stacktrace)
  end

  @doc """
  Creates a new compensation error with details about the original error and compensation attempt.

  ## Parameters

  - `original_error`: The error that triggered compensation
  - `details`: Optional map containing:
    - `:compensated` - Boolean indicating if compensation succeeded
    - `:compensation_result` - Result from successful compensation
    - `:compensation_error` - Error from failed compensation
  - `stacktrace`: Optional stacktrace for debugging

  ## Examples

      iex> original_error = Jido.Error.execution_error("Failed to process payment")
      iex> Jido.Error.compensation_error(original_error, %{
      ...>   compensated: true,
      ...>   compensation_result: %{refund_id: "ref_123"}
      ...> })
      %Jido.Error{
        type: :compensation_error,
        message: "Compensation completed for: Failed to process payment",
        details: %{
          compensated: true,
          compensation_result: %{refund_id: "ref_123"},
          original_error: %Jido.Error{...}
        }
      }

      iex> # For failed compensation:
      iex> Jido.Error.compensation_error(original_error, %{
      ...>   compensated: false,
      ...>   compensation_error: "Refund failed"
      ...> })
  """
  @spec compensation_error(t(), map(), list() | nil) :: t()
  def compensation_error(%__MODULE__{} = original_error, details, stacktrace \\ nil) do
    formatted_details = Map.put(details, :original_error, original_error)

    # Strip the error type prefix from the message if it exists
    original_message = String.replace(original_error.message, ~r/\[.*?\]\s+/, "")

    message =
      if details.compensated,
        do: "Compensation completed for: #{original_message}",
        else: "Compensation failed for: #{original_message}"

    new(:compensation_error, message, formatted_details, stacktrace)
  end

  @doc """
  Converts the error struct to a plain map.

  This function transforms the error struct into a plain map,
  including the error type and stacktrace if available. It's useful
  for serialization or when working with APIs that expect plain maps.

  ## Parameters
  - `error`: An error struct of type `t:t/0`.

  ## Returns
  A map representation of the error.

  ## Example

      iex> error = Jido.Error.validation_error("Invalid input")
      iex> Jido.Error.to_map(error)
      %{
        type: :validation_error,
        message: "Invalid input",
        stacktrace: [...]
      }
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = error) do
    error
    |> Map.from_struct()
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Captures the current stacktrace.

  This function is useful when you want to capture the stacktrace at a specific point
  in your code, rather than at the point where the error is created. It drops the first
  two entries from the stacktrace to remove internal function calls related to this module.

  ## Returns
  The current stacktrace as a list.

  ## Example

      iex> stacktrace = Jido.Error.capture_stacktrace()
      iex> is_list(stacktrace)
      true
  """
  @spec capture_stacktrace() :: list()
  def capture_stacktrace do
    {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)
    Enum.drop(stacktrace, 2)
  end

  @doc """
  Formats a NimbleOptions validation error for configuration validation.
  Used when validating configuration options at compile or runtime.

  ## Parameters
  - `error`: The NimbleOptions.ValidationError to format
  - `module_type`: String indicating the module type (e.g. "Action", "Agent", "Sensor")

  ## Examples

      iex> error = %NimbleOptions.ValidationError{keys_path: [:name], message: "is required"}
      iex> Jido.Error.format_nimble_config_error(error, "Action")
      "Invalid configuration given to use Jido.Action for key [:name]: is required"
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

  ## Parameters
  - `error`: The NimbleOptions.ValidationError to format
  - `module_type`: String indicating the module type (e.g. "Action", "Agent", "Sensor")

  ## Examples

      iex> error = %NimbleOptions.ValidationError{keys_path: [:input], message: "is required"}
      iex> Jido.Error.format_nimble_validation_error(error, "Action")
      "Invalid parameters for Action at [:input]: is required"
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
end

defimpl String.Chars, for: Jido.Error do
  @doc """
  Implements String.Chars protocol for Jido.Error.
  Returns a human-readable string representation focusing on type and message.
  """
  def to_string(%Jido.Error{type: type, message: message, details: details}) do
    base = "[#{type}] #{message}"

    if details do
      "#{base} (#{format_details(details)})"
    else
      base
    end
  end

  # Format map details with sorted keys for consistent output
  defp format_details(details) when is_map(details) do
    details
    |> Enum.reject(fn {_k, v} -> match?(%Jido.Error{}, v) end)
    |> Enum.sort_by(fn {k, _v} -> Kernel.to_string(k) end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{format_value(v)}" end)
  end

  # Handle nested map values
  defp format_value(%{} = map) do
    map_str =
      map
      |> Enum.sort_by(fn {k, _v} -> Kernel.to_string(k) end)
      |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{inspect(v)}" end)

    "%{#{map_str}}"
  end

  defp format_value(value), do: inspect(value)
end

defimpl Inspect, for: Jido.Error do
  import Inspect.Algebra

  @doc """
  Implements Inspect protocol for Jido.Error.
  Provides a detailed multi-line representation for debugging.
  """
  def inspect(error, opts) do
    # Start with basic error structure
    parts = [
      "#Jido.Error<",
      concat([
        line(),
        "  type: ",
        to_doc(error.type, opts)
      ]),
      concat([
        line(),
        "  message: ",
        to_doc(error.message, opts)
      ])
    ]

    # Add details if present
    parts =
      if error.details do
        formatted_details = format_error_details(error.details, opts)

        parts ++
          [
            concat([
              line(),
              "  details: ",
              formatted_details
            ])
          ]
      else
        parts
      end

    # Add stacktrace if present and enabled in opts
    parts =
      if error.stacktrace && opts.limit != :infinity do
        formatted_stacktrace =
          error.stacktrace
          |> Enum.take(5)
          |> Enum.map_join("\n    ", &Exception.format_stacktrace_entry/1)

        parts ++
          [
            concat([
              line(),
              "  stacktrace:",
              line(),
              "    ",
              formatted_stacktrace
            ])
          ]
      else
        parts
      end

    concat([
      concat(Enum.intersperse(parts, "")),
      line(),
      ">"
    ])
  end

  # Format details with special handling for original exceptions
  defp format_error_details(%{original_exception: exception} = details, opts)
       when not is_nil(exception) do
    # Format the exception and its stacktrace
    exception_class = exception.__struct__
    exception_message = Exception.message(exception)

    # Create a formatted version of the exception details
    exception_details = "#{exception_class}: #{exception_message}"

    # Remove the original_exception from the details map and add the formatted details
    details_without_exception =
      details
      |> Map.delete(:original_exception)
      |> Map.put(:exception_details, exception_details)

    # Format the remaining details
    to_doc(details_without_exception, opts)
    |> nest(2)
  end

  # Handle nested error in details specially (retained from original inspect_details)
  defp format_error_details(%{original_error: %Jido.Error{}} = details, opts) do
    to_doc(Map.delete(details, :original_error), opts)
    |> nest(2)
  end

  defp format_error_details(details, opts) do
    to_doc(details, opts)
    |> nest(2)
  end
end
