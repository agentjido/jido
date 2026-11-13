defmodule Jido.Examples.Durable.SavedAgent do
  @moduledoc "A report request remains committed after the entire BEAM stops."
  use Jido.Agent, name: "durable_saved_agent"

  state do
    schema Jido.Joi.object(%{
             report_id: Jido.Joi.string() |> Jido.Joi.default(""),
             topic: Jido.Joi.string() |> Jido.Joi.default(""),
             status: Jido.Joi.enum([:idle, :requested]) |> Jido.Joi.default(:idle)
           })
  end

  routes do
    signal_source "/examples/durable/saved_agent"

    route "examples.durable.saved_agent.request",
          Jido.Examples.Durable.SavedAgent.RequestReport,
          as: :request do
    end
  end
end
