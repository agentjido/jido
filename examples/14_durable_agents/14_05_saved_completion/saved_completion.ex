defmodule Jido.Examples.Durable.SavedCompletion do
  @moduledoc "Saves the report and the completed Turn in one persistence write."
  use Jido.Agent, name: "durable_saved_completion"

  state do
    schema Jido.Joi.object(%{
             report: Jido.Joi.string() |> Jido.Joi.default(""),
             completed: Jido.Joi.integer() |> Jido.Joi.default(0)
           })
  end

  routes do
    signal_source "/examples/durable/saved_completion"

    route "examples.durable.saved_completion.request",
          Jido.Examples.Durable.SavedCompletion.Report,
          as: :request do
    end
  end
end

defmodule Jido.Examples.Durable.SavedCompletion.Report do
  @moduledoc "Builds a report; AgentServer owns the final save and recovery."
  use Jido.Flow,
    name: "durable_completion_report",
    schema: Jido.Joi.object(%{topic: Jido.Joi.string() |> Jido.Joi.min(1)}),
    output_schema: Jido.Joi.object(%{report: Jido.Joi.string(), completed: Jido.Joi.integer()})

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
