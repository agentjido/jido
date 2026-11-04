defmodule Jido.Examples.Durability.RunInspection.Hold do
  use Jido.Action, name: "example_run_inspection_hold"

  @impl true
  def run(%{value: value}, %{gate: gate, observer: observer}) do
    send(Process.whereis(observer), {:inspection_waiting, self()})

    receive do
      {:release_inspection, ^gate} -> {:ok, %{value: value + 1}}
    end
  end
end

defmodule Jido.Examples.Durability.RunInspection do
  use Jido.Flow, name: "example_run_inspection"

  alias Jido.Examples.Durability.RunInspection.Hold

  flow do
    step "hold", action: Hold, params: %{value: input(:value)}
    output result("hold")
  end
end
