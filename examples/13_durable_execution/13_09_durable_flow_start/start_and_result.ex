defmodule Jido.Examples.Durability.StartAndResult.AddTax do
  use Jido.Action, name: "example_durable_add_tax"

  @impl true
  def run(%{subtotal: subtotal}, _context), do: {:ok, %{total: subtotal + 2}}
end

defmodule Jido.Examples.Durability.StartAndResult do
  @moduledoc "Runs one persisted Flow from a Signal without an Agent."
  use Jido.Flow, name: "example_durable_start_and_result"

  alias Jido.Examples.Durability.StartAndResult.AddTax

  flow do
    step "total", action: AddTax, params: %{subtotal: input(:subtotal)}
    output result("total")
  end
end
