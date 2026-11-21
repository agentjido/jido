defmodule Jido.Examples.Actions.ErrorsAndOutputValidation.CheckShipment do
  use Jido.Action,
    name: "example_action_check_shipment",
    schema: Jido.Joi.object(%{weight_kg: Jido.Joi.integer() |> Jido.Joi.min(1)}),
    output_schema: Jido.Joi.object(%{status: Jido.Joi.enum([:accepted])})

  @impl true
  def run(_params, %{mode: :reject}) do
    {:error, Jido.Error.execution_error("carrier rejected the shipment")}
  end

  def run(_params, %{mode: :invalid_output}), do: {:ok, %{status: :unknown}}
  def run(_params, _context), do: {:ok, %{status: :accepted}}
end
