defmodule Jido.Agent.Identity.Actions.Evolve do
  @moduledoc """
  Evolves agent identity profile facts over simulated time.

  This action advances an agent's identity through simulated time periods,
  allowing profile facts to change over days or years. The identity is stored
  under the reserved `:__identity__` state key.
  """

  use Jido.Action,
    name: "identity_evolve",
    description: "Evolve agent identity over simulated time",
    schema: [
      days: [type: :integer, default: 0, doc: "Days of simulated time to add"],
      years: [type: :integer, default: 0, doc: "Years of simulated time to add"]
    ]

  def run(params, ctx) do
    identity =
      case Jido.Agent.Identity.migrate_legacy(ctx.state[:__identity__]) do
        nil -> Jido.Agent.Identity.new()
        identity -> identity
      end

    evolved = Jido.Agent.Identity.evolve(identity, Map.to_list(params))
    {:ok, %{__identity__: evolved}}
  end
end
