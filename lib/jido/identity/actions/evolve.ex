defmodule Jido.Identity.Actions.Evolve do
  @moduledoc """
  Evolves agent identity over simulated time.

  This action advances an agent's identity through simulated time periods,
  allowing the identity to accumulate experiences and changes over days or years.
  The identity must already exist in the agent's state under the `__identity__` key.
  """

  use Jido.Action,
    name: "identity_evolve",
    description: "Evolve agent identity over simulated time",
    schema: [
      days: [type: :integer, default: 0, doc: "Days of simulated time to add"],
      years: [type: :integer, default: 0, doc: "Years of simulated time to add"]
    ]

  def run(params, ctx) do
    identity = ctx.state[:__identity__] || Jido.Identity.new()
    evolved = Jido.Identity.evolve(identity, Map.to_list(params))
    {:ok, %{__identity__: evolved}}
  end
end
