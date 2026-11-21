defmodule Jido.Examples.Persistence.HibernateAndThaw do
  @moduledoc "A counter that can stop after a durable save and start from that save."

  use Jido.Agent, name: "examples_hibernate_and_thaw"

  state do
    schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/examples/persistence/hibernate_and_thaw"

    route "examples.persistence.hibernate_and_thaw.increment", as: :increment do
      action %{amount: amount},
        schema: Jido.Joi.object(%{amount: Jido.Joi.integer()}),
        context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + amount}}
      end
    end
  end

  @doc "Starts this Agent only when its durable record exists."
  def thaw(jido, id), do: Jido.thaw(jido, __MODULE__, id)
end
