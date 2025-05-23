defmodule Jido.Action do
  @moduledoc """
  Defines a discrete, composable unit of functionality within the Jido system.

  Each Action represents a delayed computation that can be composed with others
  to build complex workflows. Actions are defined at compile-time
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
      description: "Performs my action",
      category: "processing",
      tags: ["example", "demo"],
      vsn: "1.0.0",
      schema: [
      input: [type: :string, required: true]
      ],
           output_schema: [
          result: [type: :string, required: true]
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

  ## AI Tool Example

  Actions can be converted to LLM compatible tools for use with LLM-based systems. This is particularly
  useful when building AI agents that need to interact with your system's capabilities:

      # Define a weather action
      iex> defmodule WeatherAction do
      ...>   use Jido.Action,
      ...>     name: "get_weather",
      ...>     description: "Gets the current weather for a location",
      ...>     category: "weather",
      ...>     tags: ["weather", "location"],
      ...>     vsn: "1.0.0",
      ...>     schema: [
      ...>       location: [
      ...>         type: :string,
      ...>         required: true,
      ...>         doc: "The city or location to get weather for"
      ...>       ]
      ...>     ]
      ...>
      ...>   @impl true
      ...>   def run(params, _context) do
      ...>     # Weather API logic here
      ...>     {:ok, %{temperature: 72, conditions: "sunny"}}
      ...>   end
      ...> end
      {:module, WeatherAction, ...}

      # Convert to tool format
      iex> WeatherAction.to_tool()
      %{
        "name" => "get_weather",
        "description" => "Gets the current weather for a location",
        "parameters" => %{
          "type" => "object",
          "properties" => %{
            "location" => %{
              "type" => "string",
              "description" => "The city or location to get weather for"
            }
          },
          "required" => ["location"]
        }
      }

  This tool definition can then be used with AI systems like OpenAI's function calling
  or other LLM frameworks that support tool/function specifications. The schema and
  validation ensure the AI system receives proper parameter constraints.

  ## Testing

  Actions can be tested directly by calling their `run/2` function with test parameters and context:

      defmodule WeatherActionTest do
        use ExUnit.Case

        test "gets weather for location" do
          params = %{location: "Portland"}
          context = %{}

          assert {:ok, result} = WeatherAction.run(params, context)
          assert is_map(result)
          assert result.temperature > 0
        end

        test "handles invalid location" do
          params = %{location: ""}
          context = %{}

          assert {:error, error} = WeatherAction.run(params, context)
          assert error.type == :validation_error
        end
      end

  For testing Actions in a more complete runtime environment, including signal routing, state
  management, and error handling, use `Jido.Exec`. This provides a full test harness for
  validating Action behavior within s:

      test "weather action in " do
        {:ok, result} = Exec.run(WeatherAction, %{location: "Seattle"})
        assert result.weather_data.temperature > 0
      end

  See `Jido.Exec` documentation for more details on action-based testing.

  ## Parameter and Output Validation

  > **Note on Validation:** The validation process for Actions is intentionally open.
  > Only fields specified in the schema and output_schema are validated. Unspecified 
  > fields are not validated, allowing for easier Action composition. This approach 
  > enables Actions to accept and pass along additional parameters that may be required 
  > by other Actions in a chain without causing validation errors.
  >
  > Output validation works the same way - only fields specified in the output_schema
  > are validated, allowing Actions to return additional data that may be used by
  > downstream Actions or systems.
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
    field(:output_schema, NimbleOptions.schema())
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
                          ],
                          output_schema: [
                            type: :keyword_list,
                            default: [],
                            doc:
                              "A NimbleOptions schema for validating the Action's output. Only specified fields are validated."
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
          description: "Performs a specific ",
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
      alias Jido.Instruction
      alias Jido.Signal

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
          def output_schema, do: @validated_opts[:output_schema]

          def to_json do
            %{
              name: @validated_opts[:name],
              description: @validated_opts[:description],
              category: @validated_opts[:category],
              tags: @validated_opts[:tags],
              vsn: @validated_opts[:vsn],
              compensation: @validated_opts[:compensation],
              schema: @validated_opts[:schema],
              output_schema: @validated_opts[:output_schema]
            }
          end

          def to_tool do
            Jido.Actions.Tool.to_tool(__MODULE__)
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

          @doc """
          Validates the output result for the Action.

          ## Examples

              iex> defmodule ExampleAction do
              ...>   use Jido.Action,
              ...>     name: "example_action",
              ...>     output_schema: [
              ...>       result: [type: :string, required: true]
              ...>     ]
              ...> end
              ...> ExampleAction.validate_output(%{result: "test", extra: "ignored"})
              {:ok, %{result: "test", extra: "ignored"}}

              iex> ExampleAction.validate_output(%{extra: "ignored"})
              {:error, "Invalid output for Action: Required key :result not found"}

          """
          @spec validate_output(map()) :: {:ok, map()} | {:error, String.t()}
          def validate_output(output) do
            with {:ok, output} <- on_before_validate_output(output),
                 {:ok, validated_output} <- do_validate_output(output),
                 {:ok, after_output} <- on_after_validate_output(validated_output) do
              OK.success(after_output)
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
                    |> Error.format_nimble_validation_error("Action", __MODULE__)
                    |> Error.validation_error()
                    |> OK.failure()
                end
            end
          end

          defp do_validate_output(output) do
            case @validated_opts[:output_schema] do
              [] ->
                OK.success(output)

              output_schema when is_list(output_schema) ->
                known_keys = Keyword.keys(output_schema)
                {known_output, unknown_output} = Map.split(output, known_keys)

                case NimbleOptions.validate(Enum.to_list(known_output), output_schema) do
                  {:ok, validated_output} ->
                    merged_output = Map.merge(unknown_output, Map.new(validated_output))
                    OK.success(merged_output)

                  {:error, %NimbleOptions.ValidationError{} = error} ->
                    error
                    |> Error.format_nimble_validation_error("Action output", __MODULE__)
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
          def on_before_validate_output(output), do: OK.success(output)
          def on_after_validate_output(output), do: OK.success(output)
          def on_after_run(result), do: OK.success(result)
          def on_error(failed_params, _error, _context, _opts), do: OK.success(failed_params)

          defoverridable on_before_validate_params: 1,
                         on_after_validate_params: 1,
                         on_before_validate_output: 1,
                         on_after_validate_output: 1,
                         run: 2,
                         on_after_run: 1,
                         on_error: 4

        {:error, error} ->
          message = Error.format_nimble_config_error(error, "Action", __MODULE__)
          raise CompileError, description: message, file: __ENV__.file, line: __ENV__.line
      end
    end
  end

  @doc """
  Executes the Action with the given parameters and context.

  This callback must be implemented by modules using `Jido.Action`.

  ## Parameters

  - `params`: A map of validated input parameters.
  - `context`: A map containing any additional context for the .

  ## Returns

  - `{:ok, result}` where `result` is a map containing the 's output.
  - `{:error, reason}` where `reason` describes why the  failed.
  """
  @callback run(params :: map(), context :: map()) ::
              {:ok, map()} | {:error, any()}

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
  Called before output validation.

  This optional callback allows for pre-processing of action output
  before it is validated against the Action's output schema.

  ## Parameters

  - `output`: A map of raw action output.

  ## Returns

  - `{:ok, modified_output}` where `modified_output` is a map of potentially modified output.
  - `{:error, reason}` if pre-processing fails.
  """
  @callback on_before_validate_output(output :: map()) :: {:ok, map()} | {:error, any()}

  @doc """
  Called after output validation.

  This optional callback allows for post-processing of validated output
  before it is returned to the caller.

  ## Parameters

  - `output`: A map of validated action output.

  ## Returns

  - `{:ok, modified_output}` where `modified_output` is a map of potentially modified output.
  - `{:error, reason}` if post-processing fails.
  """
  @callback on_after_validate_output(output :: map()) :: {:ok, map()} | {:error, any()}

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
end
