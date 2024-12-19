defmodule Jido.Action do
  @moduledoc """
  Defines a discrete, composable unit of functionality within the Jido system.

  Each Action represents a delayed computation that can be composed with others
  to build complex workflows and workflows. Actions are defined at compile-time
  and provide a consistent interface for validating inputs, executing workflows,
  and handling results.

  ## Features

  - Compile-time configuration validation
  - Runtime input parameter validation
  - Consistent error handling and formatting
  - Extensible lifecycle hooks
  - JSON serialization support

  ## Usage

  To define a new Action, use the `Jido.Action` behavior in your module:

      defmodule MyAction do
        use Jido.Action,
          name: "my_action",
          description: "Performs a specific workflow",
          category: "processing",
          tags: ["example", "demo"],
          vsn: "1.0.0",
          schema: [
            input: [type: :string, required: true]
          ]

        @impl true
        def run(params, _context) do
          # Your action logic here
          {:ok, %{result: String.upcase(params.input)}}
        end
      end

  ## Callbacks

  Implementing modules must define the following callback:

  - `c:run/2`: Executes the main logic of the Action.

  Optional callbacks for custom behavior:

  - `c:on_before_validate_params/1`: Called before parameter validation.
  - `c:on_after_validate_params/1`: Called after parameter validation.
  - `c:on_after_run/1`: Called after the Action's main logic has executed.

  ## Error Handling

  Actions use the `OK` monad for consistent error handling. Errors are wrapped
  in `Jido.Error` structs for uniform error reporting across the system.

  ## Parameter Validation

  > **Note on Validation:** The validation process for Actions is intentionally loose.
  > Only fields specified in the schema are validated. Unspecified fields are not
  > validated, allowing for easier Action composition. This approach enables Actions
  > to accept and pass along additional parameters that may be required by other
  > Actions in a chain without causing validation errors.
  """

  alias Jido.Error

  require OK

  use TypedStruct

  typedstruct do
    field(:name, String.t(), enforce: true)
    field(:description, String.t())
    field(:category, String.t())
    field(:tags, [String.t()], default: [])
    field(:vsn, String.t())
    field(:schema, NimbleOptions.schema())
  end

  @action_config_schema NimbleOptions.new!(
                          name: [
                            type: {:custom, Jido.Util, :validate_name, []},
                            required: true,
                            doc:
                              "The name of the Action. Must contain only letters, numbers, and underscores."
                          ],
                          description: [
                            type: :string,
                            required: false,
                            doc: "A description of what the Action does."
                          ],
                          category: [
                            type: :string,
                            required: false,
                            doc: "The category of the Action."
                          ],
                          tags: [
                            type: {:list, :string},
                            default: [],
                            doc: "A list of tags associated with the Action."
                          ],
                          vsn: [
                            type: :string,
                            required: false,
                            doc: "The version of the Action."
                          ],
                          compensation: [
                            type: :keyword_list,
                            default: [],
                            keys: [
                              enabled: [type: :boolean, default: false],
                              max_retries: [type: :non_neg_integer, default: 1],
                              timeout: [type: :non_neg_integer, default: 5000]
                            ]
                          ],
                          schema: [
                            type: :keyword_list,
                            default: [],
                            doc:
                              "A NimbleOptions schema for validating the Action's input parameters."
                          ]
                        )

  @doc """
  Defines a new Action module.

  This macro sets up the necessary structure and callbacks for a Action,
  including configuration validation and default implementations.

  ## Options

  #{NimbleOptions.docs(@action_config_schema)}

  ## Examples

      defmodule MyAction do
        use Jido.Action,
          name: "my_action",
          description: "Performs a specific workflow",
          schema: [
            input: [type: :string, required: true]
          ]

        @impl true
        def run(params, _context) do
          {:ok, %{result: String.upcase(params.input)}}
        end
      end

  """
  defmacro __using__(opts) do
    escaped_schema = Macro.escape(@action_config_schema)

    quote location: :keep do
      @behaviour Jido.Action

      alias Jido.Action

      require OK

      case NimbleOptions.validate(unquote(opts), unquote(escaped_schema)) do
        {:ok, validated_opts} ->
          @validated_opts validated_opts

          def name, do: @validated_opts[:name]
          def description, do: @validated_opts[:description]
          def category, do: @validated_opts[:category]
          def tags, do: @validated_opts[:tags]
          def vsn, do: @validated_opts[:vsn]
          def schema, do: @validated_opts[:schema]

          def to_json do
            %{
              name: @validated_opts[:name],
              description: @validated_opts[:description],
              category: @validated_opts[:category],
              tags: @validated_opts[:tags],
              vsn: @validated_opts[:vsn],
              compensation: @validated_opts[:compensation],
              schema: @validated_opts[:schema]
            }
          end

          def __action_metadata__ do
            to_json()
          end

          @doc """
          Validates the input parameters for the Action.

          ## Examples

              iex> defmodule ExampleAction do
              ...>   use Jido.Action,
              ...>     name: "example_action",
              ...>     schema: [
              ...>       input: [type: :string, required: true]
              ...>     ]
              ...> end
              ...> ExampleAction.validate_params(%{input: "test"})
              {:ok, %{input: "test"}}

              iex> ExampleAction.validate_params(%{})
              {:error, "Invalid parameters for Action: Required key :input not found"}

          """
          @spec validate_params(map()) :: {:ok, map()} | {:error, String.t()}
          def validate_params(params) do
            with {:ok, params} <- on_before_validate_params(params),
                 {:ok, validated_params} <- do_validate_params(params),
                 {:ok, after_params} <- on_after_validate_params(validated_params) do
              OK.success(after_params)
            else
              {:error, reason} -> OK.failure(reason)
            end
          end

          defp do_validate_params(params) do
            case @validated_opts[:schema] do
              [] ->
                OK.success(params)

              schema when is_list(schema) ->
                known_keys = Keyword.keys(schema)
                {known_params, unknown_params} = Map.split(params, known_keys)

                case NimbleOptions.validate(Enum.to_list(known_params), schema) do
                  {:ok, validated_params} ->
                    merged_params = Map.merge(unknown_params, Map.new(validated_params))
                    OK.success(merged_params)

                  {:error, %NimbleOptions.ValidationError{} = error} ->
                    error
                    |> Action.format_validation_error()
                    |> Error.validation_error()
                    |> OK.failure()
                end
            end
          end

          @doc """
          Executes the Action with the given parameters and context.

          The `run/2` function must be implemented in the module using Jido.Action.
          """
          @spec run(map(), map()) :: {:ok, map()} | {:error, any()}
          def run(params, context) do
            "run/2 must be implemented in in your Action"
            |> Error.config_error()
            |> OK.failure()
          end

          def on_before_validate_params(params), do: OK.success(params)
          def on_after_validate_params(params), do: OK.success(params)
          def on_after_run(result), do: OK.success(result)
          def on_error(failed_params, _error, _context, _opts), do: OK.success(failed_params)

          defoverridable on_before_validate_params: 1,
                         on_after_validate_params: 1,
                         run: 2,
                         on_after_run: 1,
                         on_error: 4

        {:error, error} ->
          error
          |> Action.format_config_error()
          |> Error.config_error()
          |> OK.failure()
      end
    end
  end

  @doc """
  Executes the Action with the given parameters and context.

  This callback must be implemented by modules using `Jido.Action`.

  ## Parameters

  - `params`: A map of validated input parameters.
  - `context`: A map containing any additional context for the workflow.

  ## Returns

  - `{:ok, result}` where `result` is a map containing the workflow's output.
  - `{:error, reason}` where `reason` describes why the workflow failed.
  """
  @callback run(params :: map(), context :: map()) :: {:ok, map()} | {:error, any()}

  @doc """
  Called before parameter validation.

  This optional callback allows for pre-processing of input parameters
  before they are validated against the Action's schema.

  ## Parameters

  - `params`: A map of raw input parameters.

  ## Returns

  - `{:ok, modified_params}` where `modified_params` is a map of potentially modified parameters.
  - `{:error, reason}` if pre-processing fails.
  """
  @callback on_before_validate_params(params :: map()) :: {:ok, map()} | {:error, any()}

  @doc """
  Called after parameter validation.

  This optional callback allows for post-processing of validated parameters
  before they are passed to the `run/2` function.

  ## Parameters

  - `params`: A map of validated input parameters.

  ## Returns

  - `{:ok, modified_params}` where `modified_params` is a map of potentially modified parameters.
  - `{:error, reason}` if post-processing fails.
  """
  @callback on_after_validate_params(params :: map()) :: {:ok, map()} | {:error, any()}

  @doc """
  Called after the Action's main logic has executed.

  This optional callback allows for post-processing of the Action's result
  before it is returned to the caller.

  ## Parameters

  - `result`: The result map returned by the `run/2` function.

  ## Returns

  - `{:ok, modified_result}` where `modified_result` is a potentially modified result map.
  - `{:error, reason}` if post-processing fails.
  """
  @callback on_after_run(result :: map()) :: {:ok, map()} | {:error, any()}

  @doc """
  Handles errors and performs compensation when enabled.

  Called when an error occurs during Action execution if compensation is enabled
  in the Action's configuration.

  ## Parameters

  - `failed_params`: The parameters that were passed to the failed execution
  - `error`: The Error struct describing what went wrong
  - `context`: The execution context at the time of failure
  - `opts`: Additional options for compensation handling

  ## Returns

  - `{:ok, result}` if compensation succeeded
  - `{:error, reason}` if compensation failed

  ## Examples

      def on_error(params, error, context, opts) do
        # Perform compensation logic
        case rollback_changes(params) do
          :ok -> {:ok, %{compensated: true, original_error: error}}
          {:error, reason} -> {:error, "Compensation failed: \#{reason}"}
        end
      end
  """
  @callback on_error(
              failed_params :: map(),
              error :: Error.t(),
              context :: map(),
              opts :: keyword()
            ) :: {:ok, map()} | {:error, Error.t()}

  @doc """
  Raises an error indicating that Actions cannot be defined at runtime.

  This function exists to prevent misuse of the Action system, as Actions
  are designed to be defined at compile-time only.

  ## Returns

  Always returns `{:error, reason}` where `reason` is a config error.

  ## Examples

      iex> Jido.Action.new()
      {:error, %Jido.Error{type: :config_error, message: "Actions should not be defined at runtime"}}

  """
  @spec new() :: {:error, Error.t()}
  @spec new(map() | keyword()) :: {:error, Error.t()}
  def new, do: new(%{})

  def new(_map_or_kwlist) do
    "Actions should not be defined at runtime"
    |> Error.config_error()
    |> OK.failure()
  end

  @doc """
  Formats error messages for action configuration errors.

  ## Parameters

  - `error`: The error to format. Can be a `NimbleOptions.ValidationError` or any term.

  ## Returns

  A formatted error message as a string.

  ## Examples

      iex> error = %NimbleOptions.ValidationError{keys_path: [:name], message: "is invalid"}
      iex> Jido.Action.format_config_error(error)
      "Invalid configuration given to use Jido.Action for key [:name]: is invalid"

  """
  @spec format_config_error(NimbleOptions.ValidationError.t() | any()) :: String.t()
  def format_config_error(%NimbleOptions.ValidationError{keys_path: [], message: message}) do
    "Invalid configuration given to use Jido.Action: #{message}"
  end

  def format_config_error(%NimbleOptions.ValidationError{keys_path: keys_path, message: message}) do
    "Invalid configuration given to use Jido.Action for key #{inspect(keys_path)}: #{message}"
  end

  def format_config_error(error) when is_binary(error), do: error
  def format_config_error(error), do: inspect(error)

  @doc """
  Formats error messages for action validation errors.

  ## Parameters

  - `error`: The error to format. Can be a `NimbleOptions.ValidationError` or any term.

  ## Returns

  A formatted error message as a string.

  ## Examples

      iex> error = %NimbleOptions.ValidationError{keys_path: [:input], message: "is required"}
      iex> Jido.Action.format_validation_error(error)
      "Invalid parameters for Action at [:input]: is required"

  """
  @spec format_validation_error(NimbleOptions.ValidationError.t() | any()) :: String.t()
  def format_validation_error(%NimbleOptions.ValidationError{keys_path: [], message: message}) do
    "Invalid parameters for Action: #{message}"
  end

  def format_validation_error(%NimbleOptions.ValidationError{
        keys_path: keys_path,
        message: message
      }) do
    "Invalid parameters for Action at #{inspect(keys_path)}: #{message}"
  end

  def format_validation_error(error) when is_binary(error), do: error
  def format_validation_error(error), do: inspect(error)
end
