defmodule Jido.Examples.ModelResilience.FailureTool do
  use Jido.Action,
    name: "resilience_failure_tool",
    description: "Return one deterministic retryable tool failure.",
    schema: Jido.Joi.object(%{item: Jido.Joi.string() |> Jido.Joi.min(1)})

  @impl true
  def run(_params, _context) do
    {:error, Jido.Error.execution_error("inventory unavailable", retry: true)}
  end
end

defmodule Jido.Examples.ModelResilience.ResilientAgent do
  @moduledoc "A ReAct Agent with explicit request bounds and an offline model client."

  use Jido.AI.Agent, name: "example_model_resilience_agent"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "offline:ok"
      instructions "Return a short answer."

      limits do
        elapsed_ms(5_000)
        model_calls 4
        retries 1
        tool_rounds 1
        tool_calls 1
        total_tokens(100)
        output_chars(100)
      end
    end

    tools do
      action Jido.Examples.ModelResilience.FailureTool
    end
  end
end
