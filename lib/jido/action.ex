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
  prepare raw input before its schema runs. Direct, nested, and wrapped schemas
  keep their declared Zoi unknown-key policy. Parsed struct results become
  plain maps at the Action boundary. See
  [Schemas And Validation](schemas-validation.md).

  A direct `run/2` call runs in the calling process. It does not start a task
  or add validation. Validate both boundaries explicitly when you call
  `run/2` yourself:

      {:ok, params} = MyAction.validate_params(%{input: "hello"})
      {:ok, result} = MyAction.run(params, %{})
      {:ok, result} = MyAction.validate_output(result)

  Use `Jido.Exec.run/4` when you want the public validation and error boundary.
  It validates input, calls the Action, validates normal output, and normalizes
  failures.

  Every Action must implement `run/2`. A missing implementation stops compilation.

  ## Effects and policy

  `run/2` can be pure or can perform I/O. Keep one Action focused on one unit
  of work. The caller selects retry, timeout, scheduling, cancellation, and
  persistence policy. Return an optional effect list with `{:ok, output, requests}`;
  Exec carries the requests without dispatch. `Jido.Exec` enforces a requested
  per-attempt timeout and owns process cleanup. It retries an Action only when
  the caller sets `max_attempts` and the error is retryable.
  """

  alias Jido.Action.{Error, Output}
  alias Jido.Exec.Validation

  @typedoc "A static Action input or output schema."
  @type schema :: Zoi.schema()

  @typedoc "An ordered list of opaque effect requests. Exec does not dispatch them."
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
      Validation.schema(module.schema(), params, %{context: "Action", module: module})
    end
  end

  @doc false
  @spec validate_output_for(map() | Output.t(), module()) ::
          {:ok, map() | Output.t()} | {:error, Error.InvalidInputError.t()}
  def validate_output_for(output, module) do
    Validation.output_schema(module.output_schema(), output, %{
      context: "Action output",
      module: module
    })
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
  - `schema` (optional, default: `Zoi.map()`) - A Zoi schema for Action input.
  - `output_schema` (optional, default: `Zoi.map()`) - A Zoi schema for Action output.

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

      use Jido.Authoring.Compiler,
        kind: :action,
        config: Jido.Authoring.Config.prepare!(:action, unquote(opts_ast), __ENV__)

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
  - `{:continue, continuation_input, continuation_target}` only from an Invoke
    expander, where the target becomes the next executable. Exec rejects it
    from a root Action and other Flow positions.
  - `{:error, reason}` where `reason` describes why the Action failed.
  - `{:error, reason, effects}` is accepted, but Exec discards the effects.

  - `{:handoff, successor_input, successor_target}` only from a terminal Handoff
    selector. Every execution host must handle the handoff result.
    See [Dynamic Flows](dynamic-flows.md).

  Effects are optional for both maps and Output values. An empty list returns
  the two-element success form. Exec carries each request as opaque data and
  never dispatches it. Flow collects requests from every successful executed
  component in canonical dependency order, then component name. Nested Flows
  use their parent position; collections use input or iteration order.
  Failed execution or output validation returns no effect list.

  The third success element is reserved for effect requests. Put metadata in
  the result map or in `Jido.Action.Output` metadata. A value that is not a
  proper list fails with `:invalid_effects` in direct and Flow execution.

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
end
