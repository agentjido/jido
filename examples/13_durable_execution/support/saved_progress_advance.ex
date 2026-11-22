defmodule Jido.Examples.Durable.SavedProgress.Advance do
  @moduledoc "Adds one to the value. The ten Flow steps reuse this Action."

  alias Jido.Joi

  use Jido.Action,
    name: "durable_advance",
    schema: Joi.object(%{step: Joi.integer(), value: Joi.integer()}),
    output_schema: Joi.object(%{value: Joi.integer()})

  @impl true
  def run(%{value: value}, _context), do: {:ok, %{value: value + 1}}
end
