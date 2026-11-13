defmodule Jido.Examples.Actions.TestingActions.ApplyDiscount do
  use Jido.Action,
    name: "example_action_apply_discount",
    schema:
      Jido.Joi.object(%{
        subtotal_cents: Jido.Joi.integer() |> Jido.Joi.min(0),
        discount_percent: Jido.Joi.integer() |> Jido.Joi.min(0) |> Jido.Joi.max(100)
      }),
    output_schema: Jido.Joi.object(%{total_cents: Jido.Joi.integer() |> Jido.Joi.min(0)})

  @impl true
  def run(%{subtotal_cents: subtotal, discount_percent: percent}, _context) do
    {:ok, %{total_cents: subtotal - div(subtotal * percent, 100)}}
  end
end
