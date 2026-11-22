defmodule Jido.Examples.Actions.TestingActions.ApplyDiscount do
  alias Jido.Joi

  use Jido.Action,
    name: "example_action_apply_discount",
    schema:
      Joi.object(%{
        subtotal_cents: Joi.integer() |> Joi.min(0),
        discount_percent: Joi.integer() |> Joi.min(0) |> Joi.max(100)
      }),
    output_schema: Joi.object(%{total_cents: Joi.integer() |> Joi.min(0)})

  @impl true
  def run(%{subtotal_cents: subtotal, discount_percent: percent}, _context) do
    {:ok, %{total_cents: subtotal - div(subtotal * percent, 100)}}
  end
end
