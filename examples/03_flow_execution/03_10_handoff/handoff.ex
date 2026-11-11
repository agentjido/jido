defmodule Jido.Examples.Execution.Handoff.Fulfill do
  use Jido.Action, name: "example_exec_handoff_fulfill"

  @impl true
  def run(%{order_id: order_id}, _context),
    do: {:ok, %{order_id: order_id, status: :fulfilled}}
end

defmodule Jido.Examples.Execution.Handoff.Select do
  use Jido.Action, name: "example_exec_handoff_select"
  alias Jido.Examples.Execution.Handoff.Fulfill

  @impl true
  def run(%{order_id: order_id}, _context),
    do: {:handoff, %{order_id: order_id}, Fulfill}
end

defmodule Jido.Examples.Execution.Handoff do
  use Jido.Flow, name: "example_exec_handoff"
  alias Jido.Examples.Execution.Handoff.Select

  flow do
    handoff "next", selector: Select, params: %{order_id: input(:order_id)}
    output result("next")
  end
end
