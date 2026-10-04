defmodule Jido.Examples.RecoverableDelivery do
  @moduledoc """
  An Agent commits a value and delivery intent in the same checkpoint.

  A supervised Plugin resumes pending work after restore. A later Signal
  records completion. Delivery can repeat, so the sink uses stable effect IDs.
  Ordinary Directives have no automatic replay guarantee.
  """

  use Jido.Agent, name: "example_recoverable_delivery"

  alias Jido.Examples.RecoverableDelivery.{Confirm, Deliver, MemorySink, Output}

  agent do
    schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})
    plugin Output, config: [sink: MemorySink]
  end

  routes do
    signal_source "/examples/persistence/recoverable_delivery"

    route "examples.persistence.delivery.record", as: :record_and_deliver do
      action %{effect_id: effect_id, value: value},
        schema: Zoi.object(%{effect_id: Zoi.string() |> Zoi.min(1), value: Zoi.integer()}),
        context: context do
        directive = struct!(Deliver, effect_id: effect_id, value: value)
        {:ok, %{context.agent_state | value: value}, [directive]}
      end
    end

    route "examples.persistence.delivery.confirm", as: :confirm_delivery do
      action %{effect_id: effect_id, value: value},
        schema: Zoi.object(%{effect_id: Zoi.string() |> Zoi.min(1), value: Zoi.integer()}),
        context: context do
        confirmation = struct!(Confirm, effect_id: effect_id, value: value)
        {:ok, context.agent_state, [confirmation]}
      end
    end
  end
end
