defmodule Jido.Examples.Durability.Telemetry.Add do
  use Jido.Action, name: "example_durability_telemetry_add"

  @impl true
  def run(%{value: value}, _context), do: {:ok, %{value: value + 1}}
end

defmodule Jido.Examples.Durability.Telemetry do
  use Jido.Flow, name: "example_durability_telemetry"

  alias Jido.Examples.Durability.Telemetry.Add

  flow do
    step "add", action: Add, params: %{value: input(:value)}
    output result("add")
  end
end
