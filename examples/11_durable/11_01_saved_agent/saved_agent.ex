defmodule Jido.Examples.Durable.SavedAgent do
  @moduledoc "A report request remains committed after the entire BEAM stops."
  use Jido.Agent, name: "durable_saved_agent"

  state do
    schema Zoi.object(%{
             report_id: Zoi.string() |> Zoi.default(""),
             topic: Zoi.string() |> Zoi.default(""),
             status: Zoi.enum([:idle, :requested]) |> Zoi.default(:idle)
           })
  end

  routes do
    signal_source "/examples/durable/saved_agent"

    route "examples.durable.saved_agent.request",
          Jido.Examples.Durable.SavedAgent.RequestReport,
          as: :request do
      state(from: output())
    end
  end
end
