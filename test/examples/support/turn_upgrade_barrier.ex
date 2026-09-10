defmodule JidoTest.Examples.TurnUpgradeBarrier do
  @moduledoc false
  use Jido.Action,
    name: "test_turn_upgrade_barrier",
    schema: Zoi.object(%{total: Zoi.integer(), revisions: Zoi.list(Zoi.integer())})

  def run(input, %{observer: observer, gate: gate}) do
    send(observer, {:between_upgrade_steps, gate, self()})

    receive do
      {:release, ^gate} -> {:ok, input}
    after
      5_000 -> {:error, Jido.Action.Error.execution_error("Upgrade barrier timed out")}
    end
  end

  def run(input, _context), do: {:ok, input}
end
