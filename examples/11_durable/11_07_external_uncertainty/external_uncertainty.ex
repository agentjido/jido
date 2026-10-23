defmodule Jido.Examples.Durable.ExternalUncertainty do
  @moduledoc "Reuses an operation ID when a provider call runs again after recovery."
  use Jido.Agent, name: "durable_external_uncertainty"

  state do
    schema Zoi.object(%{
             operation_id: Zoi.string() |> Zoi.default(""),
             report: Zoi.string() |> Zoi.default(""),
             status: Zoi.enum([:idle, :published, :needs_attention]) |> Zoi.default(:idle)
           })
  end

  routes do
    signal_source "/examples/durable/external_uncertainty"

    route "examples.durable.external_uncertainty.publish",
          Jido.Examples.Durable.ExternalUncertainty.Publish, as: :publish do
    end
  end
end

defmodule Jido.Examples.Durable.ExternalUncertainty.Publish do
  @moduledoc "Saves intent at a step boundary before it calls an idempotent provider."
  use Jido.Flow,
    name: "durable_publish_report",
    schema:
      Zoi.object(%{
        operation_id: Zoi.string() |> Zoi.min(1),
        report: Zoi.string() |> Zoi.min(1),
        policy: Zoi.enum([:idempotent, :manual])
      })

  flow do
    # AgentServer confirms this result before it starts the provider call.
    step "intent", request <- input() do
      {:ok, request}
    end

    step "publish", intent <- result("intent"), inline: [context: context] do
      if intent.policy == :manual do
        {:ok,
         %{operation_id: intent.operation_id, report: intent.report, status: :needs_attention}}
      else
        {provider, address} = context.publication_provider

        with :ok <- provider.publish(address, intent.operation_id, intent.report) do
          {:ok, %{operation_id: intent.operation_id, report: intent.report, status: :published}}
        end
      end
    end

    output result("publish")
  end
end
