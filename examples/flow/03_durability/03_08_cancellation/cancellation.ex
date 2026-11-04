defmodule Jido.Examples.Durability.Cancellation.Hold do
  use Jido.Action, name: "example_cancellation_hold"

  @impl true
  def run(%{label: label}, %{gate: gate, observer: observer}) do
    send(Process.whereis(observer), {:cancellation_waiting, label, self()})

    receive do
      {:release_cancellation, ^gate} -> {:ok, %{label: label}}
    end
  end
end

defmodule Jido.Examples.Durability.Cancellation do
  use Jido.Flow, name: "example_cancellation"

  alias Jido.Examples.Durability.Cancellation.Hold

  flow do
    map "items",
      collection: input(:items),
      action: Hold,
      params: %{label: item()}

    output result("items")
  end
end
