defmodule Jido.Action do
  @moduledoc """
  Defines one named, validated unit of work.

  Use `Jido.Action` in a module, declare static input and output schemas, and
  implement `c:run/2`:

      defmodule MyAction do
        use Jido.Action,
          name: "my_action",
          description: "Performs my action",
          schema: Zoi.object(%{input: Zoi.string()}),
          output_schema: Zoi.object(%{result: Zoi.string()})

        @impl true
        def run(params, _context) do
          {:ok, %{result: String.upcase(params.input)}}
        end
      end

  ## Validation and execution

  The generated `validate_params/1` and `validate_output/1` functions apply the
  declared schemas. An Action can implement `c:on_before_validate_params/1` to
  prepare raw input before its schema runs. Direct object and struct root
  schemas preserve unknown keys when their policy is `:strip`. Explicit strict
  and typed policies stay in effect. Nested and wrapped schemas keep their
  declared policy. See [Schemas And Validation](schemas-validation.md).

  A direct `run/2` call runs in the calling process. It does not start a task
  or add validation. Validate both boundaries explicitly when you call
  `run/2` yourself:

      {:ok, params} = MyAction.validate_params(%{input: "hello"})
      {:ok, result} = MyAction.run(params, %{})
      {:ok, result} = MyAction.validate_output(result)

  An execution boundary can add task isolation, input and output validation,
  failure normalization, timeout, retry, and scheduling policy around this
  callback.

  Every Action must implement `run/2`. A missing implementation stops compilation.

  ## Effects and policy

  `run/2` can be pure or can perform I/O. Keep one Action focused on one unit
  of work. The caller selects retry, timeout, scheduling, cancellation, and
  persistence policy. Return an optional request list with
  `{:ok, output, requests}`. The caller decides how to handle the requests.
  """

  alias Jido.Action.{Error, Output}
  alias Jido.Validation

  @typedoc "A static Action input or output schema."
  @type schema :: Zoi.schema() | []

  @typedoc "An ordered list of opaque effect requests for the caller."
  @type effects :: [term()]

  @typedoc "A successful output with optional deferred effect requests."
  @type effect_result :: {:ok, map() | Output.t(), effects()}

  @typedoc "A supported Action callback result."
  @type result ::
          effect_result()
          | {:ok, map() | Output.t()}
          | {:handoff, map(), Jido.Instruction.target()}
          | {:continue, map(), Jido.Instruction.target() | Jido.Instruction.t()}
          | {:error, term()}
          | {:error, term(), effects()}

  @doc false
  @spec validate_params_for(term(), module()) ::
          {:ok, map()} | {:error, term()}
  def validate_params_for(params, module) do
    with {:ok, params} <- prepare_params(params, module) do
      validate_map(
        module.schema(),
        params,
        %{context: "Action", module: module},
        "Action validation must return a map"
      )
    end
  end

  @doc false
  @spec validate_output_for(map() | Output.t(), module()) ::
          {:ok, map() | Output.t()} | {:error, Error.InvalidInputError.t()}
  def validate_output_for(%Output{} = output, _module), do: Output.validate(output)

  def validate_output_for(output, module) do
    validate_map(
      module.output_schema(),
      output,
      %{context: "Action output", module: module},
      "Action output validation must return a map"
    )
  end

  @doc """
  Defines a new Action module.

  This macro sets up the necessary structure and callbacks for an Action,
  including configuration validation and default implementations.

  ## Options

  - `name` (required) - The non-blank metadata name of the Action.
  - `id` (optional) - The stable identifier used by runtime authoring discovery.
  - `vsn` (optional, default: `1`) - The positive authoring version.
  - `description` (optional) - A description of what the Action does.
  - `schema` (optional, default: `[]`) - A Zoi schema for Action input.
  - `output_schema` (optional, default: `[]`) - A Zoi schema for Action output.

  Schemas must be static module data. Use named MFA tuples for Zoi refinements,
  transforms, and other effects. Anonymous functions and lazy schemas are not
  supported because they can change the schema after compile-time validation.

  ## Examples

      defmodule MyAction do
        use Jido.Action,
          name: "my_action",
          description: "Performs a specific task",
          schema:
            Zoi.object(%{
              input:
                Zoi.string()
                |> Zoi.refine({__MODULE__, :not_blank, []})
            })

        def not_blank(value, _opts) do
          if String.trim(value) == "", do: {:error, "cannot be blank"}, else: :ok
        end

        @impl true
        def run(params, _context) do
          {:ok, %{result: String.upcase(params.input)}}
        end
      end

  """
  defmacro __using__(opts_ast) do
    quote location: :keep do
      alias Jido.Action

      use Jido.Action.Compiler,
        config: Jido.Action.Config.prepare!(unquote(opts_ast), __ENV__)

      @doc "Executes the Action with the given parameters and context."
      @impl Jido.Action
      @spec run(map(), map()) :: Jido.Action.result()
      def run(params, context)
    end
  end

  @doc """
  Executes the Action with the given parameters and context.

  This callback must be implemented by modules using `Jido.Action`.

  ## Parameters

  - `params`: A map of validated input parameters.
  - `context`: A map that contains caller-owned execution data.

  ## Returns

  - `{:ok, result}` where `result` is a map or a `Jido.Action.Output` value.
  - `{:ok, result, effects}` where `effects` is a proper list of effect requests.
  - `{:continue, continuation_input, continuation_target}` asks the execution
    boundary to continue with another target.
  - `{:error, reason}` where `reason` describes why the Action failed.
  - `{:error, reason, effects}` returns a failure with request data.

  - `{:handoff, successor_input, successor_target}` asks the execution boundary
    to transfer ownership to another target.

  Effects are optional for both maps and Output values. An empty list returns
  the two-element success form. The execution boundary defines request order,
  delivery, and failure rules.

  The third success element is reserved for effect requests. Put metadata in
  the result map or in `Jido.Action.Output` metadata.

  A continuation does not resume this Action. Its input must be a map, not a
  `Jido.Action.Output` envelope. Put an output envelope in a map field when the
  next executable must receive it. The target must be an Action module, Flow
  module, `Jido.Flow` value, or bound `Jido.Instruction`. The final target owns
  output validation, errors, and its own effects.
  """
  @callback run(params :: map(), context :: map()) :: result()

  @doc "Validates Action input parameters without running Action work."
  @callback validate_params(params :: term()) :: {:ok, map()} | {:error, term()}

  @doc "Validates normal Action output or an explicit output envelope."
  @callback validate_output(map() | Output.t()) ::
              {:ok, map() | Output.t()} | {:error, term()}

  @doc """
  Prepares raw input parameters before schema validation.

  Use this callback only for deterministic input preparation that must happen
  before Zoi can parse the value. Prefer Zoi coercion, defaults, enums, and
  refinements when they can express the required rule.
  """
  @callback on_before_validate_params(params :: term()) ::
              {:ok, map()} | {:error, term()}

  @optional_callbacks on_before_validate_params: 1

  defp prepare_params(params, module) do
    if function_exported?(module, :on_before_validate_params, 1) do
      module.on_before_validate_params(params)
    else
      {:ok, params}
    end
  end

  defp validate_map(schema, value, details, message) do
    with {:ok, validated} <- validation_result(Validation.open_validate(schema, value, details)) do
      if is_map(validated) do
        {:ok, validated}
      else
        {:error, Error.validation_error(message, Map.put(details, :value, validated))}
      end
    end
  end

  defp validation_result({:error, %Validation.Error{} = error}),
    do: {:error, Error.validation_error(error.message, error.details)}

  defp validation_result(result), do: result
end
