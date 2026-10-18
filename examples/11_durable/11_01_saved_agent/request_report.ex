defmodule Jido.Examples.Durable.SavedAgent.RequestReport do
  @moduledoc "Normalizes, validates, and accepts a report request in one Agent Turn."
  use Jido.Flow,
    name: "durable_request_report",
    schema:
      Zoi.object(%{
        report_id: Zoi.string() |> Zoi.min(1),
        topic: Zoi.string() |> Zoi.min(1)
      }),
    output_schema:
      Zoi.object(%{
        report_id: Zoi.string(),
        topic: Zoi.string(),
        status: Zoi.enum([:idle, :requested])
      })

  flow do
    step "normalize", [report_id <- input(:report_id), topic <- input(:topic)] do
      {:ok, %{report_id: report_id, topic: String.trim(topic)}}
    end

    step "validate", request <- result("normalize") do
      if request.topic == "",
        do: {:error, Jido.Action.Error.validation_error("report topic is empty")},
        else: {:ok, request}
    end

    step "accept", request <- result("validate"), inline: [context: context] do
      if context.agent_state.status == :idle do
        {:ok,
         %{
           context.agent_state
           | report_id: request.report_id,
             topic: request.topic,
             status: :requested
         }}
      else
        {:error, Jido.Action.Error.validation_error("a report is already requested")}
      end
    end

    output result("accept")
  end
end
