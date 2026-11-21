defmodule Jido.Examples.Actions.ActionContext.CalculateQuote do
  use Jido.Action,
    name: "example_action_calculate_quote",
    schema: Jido.Joi.object(%{subtotal_cents: Jido.Joi.integer() |> Jido.Joi.min(0)}),
    output_schema:
      Jido.Joi.object(%{
        subtotal_cents: Jido.Joi.integer(),
        tax_cents: Jido.Joi.integer(),
        total_cents: Jido.Joi.integer()
      })

  @impl true
  def run(%{subtotal_cents: subtotal}, %{tax_basis_points: basis_points}) do
    tax = div(subtotal * basis_points, 10_000)
    {:ok, %{subtotal_cents: subtotal, tax_cents: tax, total_cents: subtotal + tax}}
  end

  def run(_params, _context) do
    {:error, Jido.Error.validation_error("tax_basis_points context is required")}
  end
end
