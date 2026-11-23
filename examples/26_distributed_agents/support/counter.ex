defmodule Jido.Examples.DistributedAgents.Counter do
  @moduledoc "A shared counter for the distributed Agent examples."

  alias Jido.{Joi, Signal}

  use Jido.Agent, name: "distributed_counter"

  state do
    schema Joi.object(%{count: Joi.integer() |> Joi.default(0)})
  end

  routes do
    route "examples.distribution.counter.add", as: :add do
      action %{by: by},
        schema: Joi.object(%{by: Joi.integer()}),
        context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + by}}
      end
    end
  end

  @doc "Builds a Signal that adds to the counter."
  def add(by), do: Signal.new!("examples.distribution.counter.add", %{by: by}, source: "/examples/distribution/counter")
end
