defmodule Jido.Examples.Durable.SavedProgress.Advance do
  @moduledoc "Adds one to the value. The ten Flow steps reuse this Action."
  use Jido.Action,
    name: "durable_advance",
    schema: Zoi.object(%{step: Zoi.integer(), value: Zoi.integer()}),
    output_schema: Zoi.object(%{value: Zoi.integer()})

  @impl true
  def run(%{value: value}, _context), do: {:ok, %{value: value + 1}}
end
