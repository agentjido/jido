defmodule Jido.AI do
  @moduledoc """
  A graph-first AI Agent experiment for Jido.

  `use Jido.AI.Agent` defines a normal Jido Agent with one required root
  reasoning Flow:

      defmodule MyAgent do
        use Jido.AI.Agent, name: "my_agent"

        ai do
          reasoning Jido.AI.Reasoning.ReAct
        end
      end

  The Agent owns the runtime boundary. The reasoning Flow is the direct target
  of its request route. Jido AI does not add a hidden orchestration pipeline.

  Flow components define the control behavior. The canonical ReAct recipe uses one
  shared Invoke expander for model, review, tool, and terminal decisions. A
  Flow Parallel component executes validated tool calls as separate Action
  nodes and joins their ordered results.

  Applications define their own Agent modules. A complete runnable Agent is in
  `examples/00_graph_first`.

  Select the Chain of Thought graph when one model call should return a
  variable-length numbered reasoning chain and a marked conclusion:

      ai do
        reasoning Jido.AI.Reasoning.ChainOfThought
      end

  The parsed steps are result data. The full model response enters the
  conversation as the assistant message.
  """
end
