defmodule Jido.Examples.Durable.SavedCompletion do
  @moduledoc "Saves the report and the completed Turn in one persistence write."
  use Jido.Agent, name: "durable_saved_completion"

  state do
    schema Zoi.object(%{
             report: Zoi.string() |> Zoi.default(""),
             completed: Zoi.integer() |> Zoi.default(0)
           })
  end

  routes do
    signal_source "/examples/durable/saved_completion"

    route "examples.durable.saved_completion.request",
          Jido.Examples.Durable.SavedCompletion.Report, as: :request do
    end
  end
end

defmodule Jido.Examples.Durable.SavedCompletion.Report do
  @moduledoc "Builds a report; AgentServer owns the final save and recovery."
  use Jido.Flow,
    name: "durable_completion_report",
    schema: Zoi.object(%{topic: Zoi.string() |> Zoi.min(1)}),
    output_schema: Zoi.object(%{report: Zoi.string(), completed: Zoi.integer()})

  flow do
    step "render", topic <- input(:topic) do
      {:ok, %{report: "Report: " <> topic}}
    end

    step "finish", report <- result("render", :report), inline: [context: context] do
      {:ok, %{report: report, completed: context.agent_state.completed + 1}}
    end

    output result("finish")
  end
end
