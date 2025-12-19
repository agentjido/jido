defmodule Jido.Actions.While do
  @moduledoc """
  A while loop action that executes a body action repeatedly while a condition is met.

  The While action implements a simplified while loop by evaluating the condition
  inline and executing the body action if the condition is true. This approach
  works better with the async action execution model.

  ## Parameters

  * `body` - The action module to execute on each iteration
  * `params` - Parameters that contain both condition data and body parameters
  * `condition_field` - Field name to check for truthiness (default: :continue)
  * `max_iterations` - Safety limit to prevent infinite loops (default: 100)
  * `iteration` - Current iteration count (internal, starts at 1)

  ## Condition Logic

  The condition is evaluated by checking a field in the parameters:
  * If `params[condition_field]` is truthy, continue the loop
  * If `params[condition_field]` is falsy, exit the loop

  ## Examples

      # Simple counter loop - increment while counter > 0
      %Instruction{
        action: Jido.Actions.While,
        params: %{
          body: MyApp.Actions.DecrementCounter,
          params: %{counter: 5, continue: true},
          condition_field: :continue,
          max_iterations: 10
        }
      }

      # Value accumulation with inline condition
      %Instruction{
        action: Jido.Actions.While,
        params: %{
          body: MyApp.Actions.ValueAccumulator,
          params: %{value: 0, increment: 10, max: 50},
          condition_field: :active,
          max_iterations: 20
        }
      }

  ## Execution Flow

  1. **Check Condition**: Evaluate `params[condition_field]`
  2. **If truthy**: Execute body action, then enqueue next While iteration  
  3. **If falsy**: Exit loop and return final result
  4. **Safety Check**: Abort if max_iterations exceeded

  ## Return Value

  Each iteration returns metadata about the current loop state:
  * `iteration` - Current iteration number (1-based)
  * `body` - The body action being executed
  * `continue` - Whether the loop will continue (based on condition)
  * `final` - Present and `true` only when loop exits

  ## Safety Features

  * **Max Iterations**: Prevents runaway loops with configurable limit
  * **Simple Conditions**: Uses inline parameter checking for reliability
  * **State Preservation**: Loop parameters can be updated by body actions

  ## Parameter Passing Between Iterations

  Body actions can influence the next iteration's parameters by returning extra
  metadata in their result tuple:

      # Body action can return updated parameters for next iteration
      def run(params, context) do
        new_value = params.value + 1
        continue = new_value < params.max
        
        {:ok, 
         %{value: new_value, continue: continue},
         %{next_params: %{params | value: new_value, continue: continue}}}
      end

  The While action will detect the `:next_params` key and merge those parameters
  into the next iteration's execution.
  """

  use Jido.Action,
    name: "while",
    description: "Executes a body action while a condition field is truthy",
    schema: [
      body: [type: :atom, required: true, doc: "Body action module to execute each iteration"],
      params: [type: :map, default: %{}, doc: "Parameters containing condition and body data"],
      condition_field: [
        type: :atom,
        default: :continue,
        doc: "Field name to check for truthiness"
      ],
      max_iterations: [type: :pos_integer, default: 100, doc: "Maximum loop iterations"],
      iteration: [type: :pos_integer, default: 1, doc: "Current iteration (internal)"]
    ],
    output_schema: [
      iteration: [type: :pos_integer, required: true, doc: "Current iteration number"],
      body: [type: :atom, required: true, doc: "Body action module"],
      condition_field: [type: :atom, required: true, doc: "Field name checked for condition"],
      continue: [type: :boolean, required: true, doc: "Whether loop will continue"],
      final: [type: :boolean, doc: "Present and true only when loop exits"]
    ]

  alias Jido.Agent.Directive.Enqueue

  @impl true
  def run(%{max_iterations: max, iteration: i}, _ctx) when i > max,
    do: {:error, "Maximum iterations (#{max}) exceeded"}

  @impl true
  def run(%{body: body_mod, params: p, condition_field: field} = args, _ctx) do
    continue? = !!Map.get(p, field, false)

    common_meta = %{
      iteration: args.iteration,
      body: body_mod,
      condition_field: field,
      continue: continue?
    }

    if continue? do
      {:ok, common_meta,
       [
         enqueue(body_mod, p),
         enqueue(__MODULE__, %{args | iteration: args.iteration + 1})
       ]}
    else
      {:ok, Map.put(common_meta, :final, true)}
    end
  end

  @impl true
  def on_after_run({:ok, meta, [body_directive, next_directive]} = full) do
    case meta do
      %{next_params: new_params} when is_map(new_params) ->
        updated_next = put_in(next_directive.params.params, new_params)
        {:ok, meta, [body_directive, updated_next]}

      _ ->
        full
    end
  end

  def on_after_run(result), do: {:ok, result}

  defp enqueue(mod, params), do: %Enqueue{action: mod, params: params, context: %{}}
end
