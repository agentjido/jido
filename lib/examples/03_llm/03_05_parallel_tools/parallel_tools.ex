defmodule Jido.Examples.ParallelTools.Finish do
  @moduledoc false
  alias Jido.Examples.ToolCall.Finish
  use Jido.Action, name: "llm_parallel_finish"

  def run(input, context) do
    # beta.4 Map errors have no call ID. Recover correlation from the admitted
    # plan's stable position. Do not claim a structured upstream cause here.
    results =
      Enum.zip_with(input.calls, input.results, fn call, result ->
        case result do
          %{status: :ok, value: value} -> Map.put(value, :id, call.id)
          error -> Map.put(error, :id, call.id)
        end
      end)

    Finish.run(%{prompt: input.prompt, results: results}, context)
  end
end

defmodule Jido.Examples.ParallelTools.Pipeline do
  @moduledoc "Admit the complete plan, run Map, and preserve each result position for the model."
  alias Jido.Examples.LLM.Adapter
  alias Jido.Examples.ToolCall.Admit
  use Jido.Flow, name: "llm_parallel_tools", schema: Adapter.prompt_schema()

  flow do
    step "select" do
      action prompt <- input(:prompt), context: context do
        with {:ok, raw} <- Adapter.call(context, :model, :select, %{prompt: prompt}),
             {:ok, calls} <- Admit.plan(raw),
             do: {:ok, %{calls: calls}}
      end
    end

    map "tools",
      collection: result("select", :calls),
      action: Jido.Examples.ToolCall.Search,
      params: item(),
      on_error: :collect_errors

    step "answer",
      action: Jido.Examples.ParallelTools.Finish,
      params: %{prompt: input(:prompt), calls: result("select", :calls), results: result("tools")}

    output result("answer")
  end
end

defmodule Jido.Examples.ParallelTools do
  @moduledoc "Parallel model-selected tools use the SDK Map concurrency bound."

  use Jido.Agent, name: "llm_parallel_tools_agent"

  agent do
    schema Zoi.object(%{
             answer: Zoi.string() |> Zoi.default(""),
             tool_results: Zoi.list(Zoi.map()) |> Zoi.default([])
           })
  end

  routes do
    signal_source "/examples/llm"

    route "llm.parallel", Jido.Examples.ParallelTools.Pipeline do
      define :plan, args: [:prompt]
    end
  end
end
