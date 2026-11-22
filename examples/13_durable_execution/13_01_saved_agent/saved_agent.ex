defmodule Jido.Examples.Durable.SavedAgent do
  @moduledoc "A report request remains committed after the entire BEAM stops."

  alias Jido.Joi

  use Jido.Agent, name: "durable_saved_agent"

  state do
    schema Joi.object(%{
             report_id: Joi.string() |> Joi.default(""),
             topic: Joi.string() |> Joi.default(""),
             status: Joi.enum([:idle, :requested]) |> Joi.default(:idle)
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
