defmodule Jido.Examples.ParallelTools do
  @moduledoc "Runs a validated model tool plan with the Flow Map concurrency bound."

  use Jido.Agent, name: "examples_llm_parallel_tools"

  agent do
    schema Zoi.object(%{
             answer: Zoi.string() |> Zoi.default(""),
             tool_results: Zoi.list(Zoi.map()) |> Zoi.default([])
           })
  end

  routes do
    signal_source "/examples/llm/parallel_tools"

    route "examples.llm.parallel_tools.plan", Jido.Examples.ParallelTools.Pipeline do
      define :plan, args: [:prompt]
    end
  end
end

defmodule Jido.Examples.ParallelTools.Pipeline do
  @moduledoc "Validates the complete plan and keeps result order after parallel work."

  alias Jido.Examples.LLM.{Adapter, FinishAnswer, SearchTool, ToolPlan}

  use Jido.Flow,
    name: "examples_llm_parallel_tools_flow",
    schema: Adapter.prompt_schema()

  flow do
    step "select" do
      action prompt <- input(:prompt),
             schema: Adapter.prompt_schema(),
             context: context do
        with {:ok, raw} <- Adapter.call(context, :model, :select, %{prompt: prompt}),
             {:ok, calls} <- ToolPlan.parse(raw) do
          {:ok, %{calls: calls}}
        end
      end
    end

    map "tools",
      collection: result("select", :calls),
      action: SearchTool,
      params: item(),
      on_error: :collect_errors

    step "correlate" do
      action %{prompt: prompt, calls: calls, results: tool_results} <- %{
               prompt: input(:prompt),
               calls: result("select", :calls),
               results: result("tools")
             },
             schema:
               Zoi.object(%{
                 prompt: Zoi.string() |> Zoi.min(1),
                 calls: Zoi.list(Zoi.map()),
                 results: Zoi.list(Zoi.map())
               }) do
        # Map errors do not include the call ID. The admitted plan position is
        # stable, so it restores correlation before the final model call.
        results =
          Enum.zip_with(calls, tool_results, fn call, result ->
            case result do
              %{status: :ok, value: value} -> Map.put(value, :id, call.id)
              error -> Map.put(error, :id, call.id)
            end
          end)

        {:ok, %{prompt: prompt, results: results}}
      end
    end

    step "answer",
      action: FinishAnswer,
      params: result("correlate")

    output result("answer")
  end
end
