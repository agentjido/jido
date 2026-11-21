defmodule Jido.BehaviorTree.Skill do
  @moduledoc """
  Runs a standalone tree as a tool and returns its final blackboard.

  Supply Joi schemas for the tool parameters and result. The tree gets the
  parsed parameters on its blackboard. The wrapper rejects Directives because
  tool execution has no AgentServer to own post-commit work.
  """

  alias Jido.BehaviorTree.{Blackboard, Error, Tick, Tree}
  alias Jido.Joi

  @schema Joi.struct(
            __MODULE__,
            %{
              name: Joi.string(description: "The name of the skill"),
              description: Joi.string(description: "Description of what the skill does") |> Joi.default(""),
              tree: Joi.any(description: "The behavior tree to execute"),
              schema:
                Joi.any(description: "Joi input parameter schema")
                |> Joi.default(Joi.object(%{})),
              output_schema: Joi.any(description: "Output validation schema") |> Joi.default(Joi.object(%{})),
              timeout:
                Joi.integer(description: "Execution timeout in milliseconds")
                |> Joi.min(0)
                |> Joi.default(30_000),
              auto_mode: Joi.boolean(description: "Whether to run in automatic mode") |> Joi.default(false),
              interval:
                Joi.integer(description: "Tick interval for auto mode")
                |> Joi.min(0)
                |> Joi.default(1000)
            },
            coerce: true
          )

  @type t :: unquote(Joi.type_spec(@schema))

  @enforce_keys Joi.enforce_keys(@schema)
  defstruct Joi.struct_fields(@schema)

  @doc "Returns the Joi schema for this module"
  def schema, do: @schema

  @doc """
  Creates a tree tool. Options include `:schema`, `:output_schema`,
  `:timeout` in milliseconds, `:auto_mode`, and `:interval` in milliseconds.
  Auto mode waits one interval before each tick. Manual mode ticks immediately
  and waits 10 milliseconds between running ticks.
  """
  @spec new(String.t(), Tree.t(), String.t(), keyword()) :: t()
  def new(name, tree, description \\ "", opts \\ []) do
    struct!(__MODULE__, Keyword.merge([name: name, tree: tree, description: description], opts))
  end

  @doc "Returns an OpenAI-style tool definition."
  @spec to_tool(t()) :: map()
  def to_tool(%__MODULE__{} = skill) do
    %{
      "name" => skill.name,
      "description" => skill.description,
      "parameters" => skill.schema |> Joi.to_json_schema() |> JSON.encode!() |> JSON.decode!()
    }
  end

  @doc """
  Executes a tree with the parsed parameters on its initial blackboard.

  The timeout is checked between ticks. Node callbacks must return promptly.
  The supplied context is available to nodes for the duration of the run.
  """
  @spec run(t(), map(), map()) :: {:ok, map()} | {:error, term()}
  def run(%__MODULE__{} = skill, params, context) do
    with {:ok, parsed} <- Jido.Agent.Directive.parse(skill.schema, params) do
      tick = Tick.new_with_context(Blackboard.new(parsed), nil, [], context)
      deadline = System.monotonic_time(:millisecond) + skill.timeout
      interval = if skill.auto_mode, do: skill.interval, else: 0

      run_tree(skill.tree, tick, skill, deadline, interval)
    end
  end

  defp run_tree(tree, tick, skill, deadline, delay) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= delay do
      finish(tree, {:error, Error.execution_error("Execution timed out")})
    else
      if delay > 0, do: Process.sleep(delay)
      {status, tree, tick} = Tree.tick_with_context(tree, tick)

      cond do
        System.monotonic_time(:millisecond) >= deadline ->
          finish(tree, {:error, Error.execution_error("Execution timed out")})

        tick.directives != [] ->
          finish(tree, {:error, Error.execution_error("Behavior Tree tools cannot return Directives")})

        status == :running ->
          interval = if skill.auto_mode, do: skill.interval, else: 10
          run_tree(tree, Tick.increment_sequence(tick), skill, deadline, interval)

        true ->
          finish(tree, tool_result(status, tick, skill.output_schema))
      end
    end
  end

  defp tool_result(:success, tick, schema),
    do: Jido.Agent.Directive.parse(schema, Blackboard.to_map(tick.blackboard))

  defp tool_result(:failure, _tick, _schema), do: {:error, Error.execution_error("Behavior tree failed")}

  defp tool_result({:error, reason}, _tick, _schema),
    do: {:error, Error.execution_error("Behavior tree error", %{reason: reason})}

  defp finish(tree, result) do
    _halted = Tree.halt(tree)
    result
  end
end
