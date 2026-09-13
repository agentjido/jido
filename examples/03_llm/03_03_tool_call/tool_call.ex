defmodule Jido.Examples.ToolCall do
  @moduledoc "One approved typed tool call followed by a checked model answer."

  use Jido.Agent, name: "examples_llm_tool_call"

  agent do
    schema Zoi.object(%{
             answer: Zoi.string() |> Zoi.default(""),
             tool_results: Zoi.list(Zoi.map()) |> Zoi.default([])
           })
  end

  routes do
    signal_source "/examples/llm/tool_call"

    route "examples.llm.tool_call.ask", Jido.Examples.ToolCall.Pipeline do
      define :ask, args: [:prompt]
    end
  end
end

defmodule Jido.Examples.ToolCall.Pipeline do
  @moduledoc "Selects one approved tool and retains its model call ID."

  alias Jido.Examples.LLM.{Adapter, FinishAnswer, SearchTool, ToolPlan}

  use Jido.Flow,
    name: "examples_llm_single_tool_flow",
    schema: Adapter.prompt_schema()

  flow do
    step "select",
         prompt <- input(:prompt),
         inline: [schema: Adapter.prompt_schema(), context: context] do
      with {:ok, raw} <- Adapter.call(context, :model, :select, %{prompt: prompt}),
           {:ok, [call]} <- ToolPlan.parse([raw]) do
        {:ok, call}
      end
    end

    step "tool", action: SearchTool, params: result("select")

    step "answer",
      action: FinishAnswer,
      params: %{prompt: input(:prompt), results: [result("tool")]}

    output result("answer")
  end
end
