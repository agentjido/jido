defmodule Jido.Examples.Durable.SavedProgress.Advance do
  @moduledoc "Adds one to the value. The ten Flow steps reuse this Action."
  use Jido.Action,
    name: "durable_advance",
    schema: Jido.Joi.object(%{step: Jido.Joi.integer(), value: Jido.Joi.integer()}),
    output_schema: Jido.Joi.object(%{value: Jido.Joi.integer()})

  @impl true
  def run(%{value: value}, _context), do: {:ok, %{value: value + 1}}
end
