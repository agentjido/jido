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
  - Any other keys are merged into `details`
  """
  @spec execution_error(String.t(), keyword() | map()) :: ExecutionError.t()
  def execution_error(message, opts \\ []) do
    opts = if is_map(opts), do: Map.to_list(opts), else: opts
    details = merge_extra_details(opts, [:phase])

    ExecutionError.exception(
      message: message,
      phase: Keyword.get(opts, :phase, :execution),
      details: details
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

  defp merge_extra_details(opts, reserved_keys) do
    explicit_details =
      case Keyword.get(opts, :details, %{}) do
        details when is_map(details) -> details
        _ -> %{}
      end

    extra_details =
      opts
      |> Keyword.drop([:details | reserved_keys])
      |> Enum.into(%{})

    Map.merge(extra_details, explicit_details)
  end

  # ============================================================================
  # Utilities
  # ============================================================================

  @transport_max_depth 4
  @transport_max_items 20
  @transport_max_string 512
  @transport_inspect_limit 50
  @transport_printable_limit 200
  @non_retryable_error_type_strings ~w[
    validation_error
    invalid_action
    invalid_sensor
    config_error
  ]
  @known_error_type_strings %{
    "validation_error" => :validation_error,
    "invalid_action" => :invalid_action,
    "invalid_sensor" => :invalid_sensor,
    "config_error" => :config_error,
    "planning_error" => :planning_error,
    "execution_error" => :execution_error,
    "routing_error" => :routing_error,
    "timeout" => :timeout,
    "compensation_error" => :compensation_error,
    "internal" => :internal
  }
  @redacted "[REDACTED]"
  @omitted "[OMITTED]"
  @depth_limit "[DEPTH_LIMIT]"
  @sensitive_key_parts MapSet.new(~w[
    api_key
    apikey
    authorization
    credential
    credentials
    password
    private_key
    secret
    token
  ])
  @sensitive_key_fragments ~w[
    apikey
    authorization
    credential
    credentials
    password
    privatekey
    secret
    token
  ]

  @doc """
  Converts an error into a stable, public map.

  The returned map is suitable for transport and reporting boundaries. It
  includes bounded, sanitized details and never includes stacktraces by default.
  """
  @spec to_map(any()) :: map()
  def to_map(error) do
    %{
      type: unified_type(error),
      message: public_message(error),
      details: public_details(error),
      retryable?: retryable?(error)
    }
  end

  @doc """
  Returns whether an error is safe to retry by default.

  Explicit `:retry`, `:retryable`, and `:retryable?` boolean hints in structured
  details override the default classification.
  """
  @spec retryable?(term()) :: boolean()
  def retryable?({:error, reason, _effects}), do: retryable?(reason)
  def retryable?({:error, reason}), do: retryable?(reason)
  def retryable?(%ValidationError{details: details}), do: retryable_hint(details, false)

  def retryable?(%ExecutionError{details: details} = error),
    do: retryable_hint(details, default_retryable?(error))

  def retryable?(%RoutingError{details: details} = error),
    do: retryable_hint(details, default_retryable?(error))

  def retryable?(%TimeoutError{details: details} = error),
    do: retryable_hint(details, default_retryable?(error))

  def retryable?(%CompensationError{details: details} = error),
    do: retryable_hint(details, default_retryable?(error))

  def retryable?(%InternalError{details: details} = error),
    do: retryable_hint(details, default_retryable?(error))

  def retryable?(%Internal.UnknownError{details: details} = error),
    do: retryable_hint(details, default_retryable?(error))

  def retryable?(%{retryable?: value}) when is_boolean(value), do: value
  def retryable?(%{retryable: value}) when is_boolean(value), do: value
  def retryable?(%{"retryable" => value}) when is_boolean(value), do: value
  def retryable?(%{"retryable?" => value}) when is_boolean(value), do: value

  def retryable?(%{type: type} = error) when is_atom(type),
    do: retryable_hint(Map.get(error, :details, error), default_retryable_for_type?(type))

  def retryable?(%{type: type} = error) when is_binary(type),
    do: retryable_hint(Map.get(error, :details, error), default_retryable_for_type?(type))

  def retryable?(%{"type" => type} = error) when is_atom(type),
    do: retryable_hint(Map.get(error, "details", error), default_retryable_for_type?(type))

  def retryable?(%{"type" => type} = error) when is_binary(type),
    do: retryable_hint(Map.get(error, "details", error), default_retryable_for_type?(type))

  def retryable?(%{details: details} = error),
    do: retryable_hint(details, default_retryable?(error))

  def retryable?(%{"details" => details} = error),
    do: retryable_hint(details, default_retryable?(error))

  def retryable?(reason) when is_atom(reason), do: default_retryable?(reason)
  def retryable?(_reason), do: true

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

  defp public_message(error) when is_exception(error),
    do: truncate_string(Exception.message(error))

  defp public_message(%{message: message}), do: transport_string(message)
  defp public_message(%{"message" => message}), do: transport_string(message)
  defp public_message(error), do: error |> sanitize_transport() |> safe_inspect()

  defp public_details(%ValidationError{} = error) do
    error.details
    |> sanitize_details()
    |> merge_public_fields(%{
      kind: error.kind,
      subject: error.subject
    })
  end

  defp public_details(%ExecutionError{} = error) do
    error.details
    |> sanitize_details()
    |> merge_public_fields(%{phase: error.phase})
  end

  defp public_details(%RoutingError{} = error) do
    error.details
    |> sanitize_details()
    |> merge_public_fields(%{target: error.target})
  end

  defp public_details(%TimeoutError{} = error) do
    error.details
    |> sanitize_details()
    |> merge_public_fields(%{timeout: error.timeout})
  end

  defp public_details(%CompensationError{} = error) do
    error.details
    |> sanitize_details()
    |> merge_public_fields(%{
      original_error: maybe_error_map(error.original_error),
      compensated: error.compensated,
      result: error.result
    })
  end

  defp public_details(%{details: details}), do: sanitize_details(details)
  defp public_details(%{"details" => details}), do: sanitize_details(details)
  defp public_details(_error), do: %{}

  defp maybe_error_map(nil), do: nil
  defp maybe_error_map(error), do: to_map(error)

  defp sanitize_details(details) when is_map(details), do: sanitize_transport(details)
  defp sanitize_details(details) when details in [nil, []], do: %{}
  defp sanitize_details(details), do: %{value: sanitize_transport(details)}

  defp merge_public_fields(details, fields) do
    fields
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn {key, value} -> {key, sanitize_transport(value)} end)
    |> then(&Map.merge(details, &1))
  end

  defp sanitize_transport(value, depth \\ @transport_max_depth)
  defp sanitize_transport(_value, 0), do: @depth_limit
  defp sanitize_transport(value, _depth) when is_binary(value), do: truncate_string(value)

  defp sanitize_transport(value, _depth)
       when is_boolean(value) or is_number(value) or is_atom(value),
       do: value

  defp sanitize_transport(%_{} = value, _depth) when is_exception(value) do
    %{
      type: value.__struct__ |> Module.split() |> Enum.join("."),
      message: truncate_string(Exception.message(value))
    }
  end

  defp sanitize_transport(%_{} = value, depth) do
    value
    |> Map.from_struct()
    |> Map.put(:struct, value.__struct__)
    |> sanitize_transport(depth)
  rescue
    _ -> safe_inspect(value)
  end

  defp sanitize_transport(value, depth) when is_map(value) do
    sanitize_key_value_pairs(value, depth)
  end

  defp sanitize_transport(value, depth) when is_list(value) do
    if key_value_list?(value) do
      sanitize_key_value_pairs(value, depth)
    else
      value
      |> Enum.take(@transport_max_items)
      |> Enum.map(&sanitize_transport(&1, depth - 1))
    end
  end

  defp sanitize_transport(value, _depth) when is_tuple(value), do: safe_inspect(value)
  defp sanitize_transport(value, _depth) when is_function(value), do: safe_inspect(value)
  defp sanitize_transport(value, _depth) when is_pid(value), do: safe_inspect(value)
  defp sanitize_transport(value, _depth) when is_reference(value), do: safe_inspect(value)
  defp sanitize_transport(value, _depth), do: safe_inspect(value)

  defp sanitize_key(key) when is_atom(key) or is_binary(key), do: key
  defp sanitize_key(key), do: safe_inspect(key)

  defp sanitize_key_value_pairs(entries, depth) do
    entries
    |> Enum.take(@transport_max_items)
    |> Map.new(fn {key, nested_value} ->
      sanitized_key = sanitize_key(key)

      nested_value =
        cond do
          sensitive_key?(sanitized_key) -> @redacted
          stacktrace_key?(sanitized_key) -> @omitted
          true -> sanitize_transport(nested_value, depth - 1)
        end

      {sanitized_key, nested_value}
    end)
  end

  defp key_value_list?(value) do
    value != [] and
      Enum.all?(value, fn
        {key, _value} when is_atom(key) or is_binary(key) -> true
        _other -> false
      end)
  end

  defp sensitive_key?(key) do
    normalized_key = normalized_key(key)
    key_parts = key_parts(normalized_key)
    compact_key = compact_key(normalized_key)

    MapSet.member?(@sensitive_key_parts, normalized_key) ||
      Enum.any?(key_parts, &MapSet.member?(@sensitive_key_parts, &1)) ||
      Enum.any?(@sensitive_key_fragments, &String.contains?(compact_key, &1))
  end

  defp stacktrace_key?(key) do
    normalized_key = normalized_key(key)
    compact_key = compact_key(normalized_key)

    normalized_key in ["stacktrace", "stack_trace"] ||
      "stacktrace" in key_parts(normalized_key) ||
      String.contains?(compact_key, "stacktrace")
  end

  defp normalized_key(key) when is_atom(key), do: key |> Atom.to_string() |> String.downcase()
  defp normalized_key(key) when is_binary(key), do: String.downcase(key)

  defp key_parts(key), do: String.split(key, ~r/[^a-z0-9]+/, trim: true)
  defp compact_key(key), do: String.replace(key, ~r/[^a-z0-9]+/, "")

  defp transport_string(value) when is_binary(value), do: truncate_string(value)
  defp transport_string(%{message: message}), do: transport_string(message)
  defp transport_string(value), do: value |> sanitize_transport() |> safe_inspect()

  defp safe_inspect(value) do
    value
    |> inspect(limit: @transport_inspect_limit, printable_limit: @transport_printable_limit)
    |> truncate_string()
  rescue
    _ -> inspect_fallback(value)
  end

  defp inspect_fallback(value) do
    module =
      case value do
        %{__struct__: struct} when is_atom(struct) -> inspect(struct)
        _ -> value |> :erlang.term_to_binary() |> byte_size() |> then(&"#{&1} bytes")
      end

    "#Inspect.Error<#{module}>"
  end

  defp truncate_string(value, max_chars \\ @transport_max_string) when is_binary(value) do
    if String.length(value) > max_chars do
      String.slice(value, 0, max_chars) <> "...(truncated)"
    else
      value
    end
  end

  defp retryable_hint(term, default) do
    case extract_retry_hint(term) do
      value when is_boolean(value) -> value
      _ -> default
    end
  end

  defp extract_retry_hint(%{details: details}) do
    case extract_retry_hint(details) do
      nil -> nil
      value -> value
    end
  end

  defp extract_retry_hint(%{} = map) do
    cond do
      is_boolean(Map.get(map, :retry)) -> Map.get(map, :retry)
      is_boolean(Map.get(map, "retry")) -> Map.get(map, "retry")
      is_boolean(Map.get(map, :retryable)) -> Map.get(map, :retryable)
      is_boolean(Map.get(map, "retryable")) -> Map.get(map, "retryable")
      is_boolean(Map.get(map, :retryable?)) -> Map.get(map, :retryable?)
      is_boolean(Map.get(map, "retryable?")) -> Map.get(map, "retryable?")
      Map.has_key?(map, :reason) -> extract_retry_hint(Map.get(map, :reason))
      Map.has_key?(map, "reason") -> extract_retry_hint(Map.get(map, "reason"))
      true -> nil
    end
  end

  defp extract_retry_hint(keyword) when is_list(keyword) do
    if Keyword.keyword?(keyword) do
      cond do
        is_boolean(Keyword.get(keyword, :retry)) -> Keyword.get(keyword, :retry)
        is_boolean(Keyword.get(keyword, :retryable)) -> Keyword.get(keyword, :retryable)
        is_boolean(Keyword.get(keyword, :retryable?)) -> Keyword.get(keyword, :retryable?)
        true -> nil
      end
    end
  end

  defp extract_retry_hint(_term), do: nil

  defp default_retryable?(type) when is_atom(type), do: default_retryable_for_type?(type)
  defp default_retryable?(error), do: error |> unified_type() |> default_retryable_for_type?()

  defp default_retryable_for_type?(type)
       when type in [:validation_error, :invalid_action, :invalid_sensor, :config_error],
       do: false

  defp default_retryable_for_type?(type) when is_binary(type),
    do: normalize_type_string(type) not in @non_retryable_error_type_strings

  defp default_retryable_for_type?(_type), do: true

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

  defp unified_type(%{type: type}) when is_atom(type), do: type
  defp unified_type(%{type: type}) when is_binary(type), do: unified_type_from_string(type)
  defp unified_type(%{"type" => type}) when is_atom(type), do: type
  defp unified_type(%{"type" => type}) when is_binary(type), do: unified_type_from_string(type)

  defp unified_type(_), do: :internal

  defp unified_type_from_string(type) do
    Map.get(@known_error_type_strings, normalize_type_string(type), :internal)
  end

  defp normalize_type_string(type) do
    type
    |> String.trim()
    |> String.trim_leading(":")
  end
end
