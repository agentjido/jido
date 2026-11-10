defmodule Jido.Examples.Durability.DirectFlow.AddTax do
  use Jido.Action, name: "example_durable_add_tax"

  @impl true
  def run(%{subtotal: subtotal}, _context), do: {:ok, %{total: subtotal + 2}}
end

defmodule Jido.Examples.Durability.DirectFlow do
  @moduledoc "Runs one persisted Flow without an Agent."
  use Jido.Flow, name: "example_durable_direct_flow"

  alias Jido.Examples.Durability.DirectFlow.AddTax

  flow do
    step "total", action: AddTax, params: %{subtotal: input(:subtotal)}
    output result("total")
  end
end
