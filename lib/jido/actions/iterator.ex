defmodule Jido.Actions.Iterator do
  @moduledoc """
  An action that executes another action multiple times in sequence.

  The Iterator action wraps any other action and executes it a specified number of times,
  creating a cascading chain of enqueued actions. This is useful for batch processing,
  repeated operations, or implementing simple loops within the agent system.

  ## Parameters

  * `action` - The action module to execute repeatedly
  * `count` - Number of times to execute the target action (minimum: 1)
  * `params` - Parameters to pass to each execution of the target action
  * `index` - Current iteration index (internal, starts at 1)

  ## Examples

      # Execute Add action 5 times with the same parameters
      %Instruction{
        action: Jido.Actions.Iterator,
        params: %{
          action: MyApp.Actions.Add,
          count: 5, 
          params: %{value: 10, amount: 2}
        }
      }

      # Execute a cleanup action 3 times
      %Instruction{
        action: Jido.Actions.Iterator,
        params: %{
          action: MyApp.Actions.Cleanup,
          count: 3,
          params: %{directory: "/tmp/cache"}
        }
      }

  ## Execution Flow

  The Iterator creates a chain where each iteration enqueues:
  1. The target action with the specified parameters
  2. The next iteration of the Iterator (if more iterations remain)

  This creates a sequential execution pattern where actions are processed
  one after another by the agent server's runtime.

  ## Return Value

  Each iteration returns metadata about the current execution:
  * `index` - Current iteration number (1-based)
  * `count` - Total number of iterations
  * `action` - The target action being executed
  * `params` - Parameters being passed to the target action
  * `final` - Present and `true` only on the last iteration
  """

  use Jido.Action,
    name: "iterator",
    description: "Executes another action multiple times in sequence",
    schema: [
      action: [type: :atom, required: true, doc: "Action module to execute repeatedly"],
      count: [type: :pos_integer, required: true, doc: "Number of executions (minimum: 1)"],
      params: [type: :map, default: %{}, doc: "Parameters for target action"],
      index: [type: :pos_integer, default: 1, doc: "Current iteration (internal)"]
    ],
    output_schema: [
      index: [type: :pos_integer, required: true, doc: "Current iteration number"],
      count: [type: :pos_integer, required: true, doc: "Total number of iterations"],
      action: [type: :atom, required: true, doc: "Target action being executed"],
      params: [type: :map, required: true, doc: "Parameters passed to target action"],
      final: [type: :boolean, doc: "Present and true only on last iteration"]
    ]

  alias Jido.Agent.Directive.Enqueue

  @impl true
  def run(%{count: c}, _ctx) when c <= 0,
    do: {:error, "Count must be positive"}

  @impl true
  def run(%{action: mod, count: c, params: p, index: i} = args, _ctx) when i <= c do
    next = if i < c, do: [enqueue(__MODULE__, %{args | index: i + 1})], else: []

    {:ok,
     %{
       index: i,
       count: c,
       action: mod,
       params: p,
       final: i == c
     }, [enqueue(mod, p) | next]}
  end

  defp enqueue(mod, params), do: %Enqueue{action: mod, params: params, context: %{}}
end
