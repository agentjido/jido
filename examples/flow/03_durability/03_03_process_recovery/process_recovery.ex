defmodule Jido.Examples.Durability.ProcessRecovery.Record do
  use Jido.Action, name: "example_process_recovery_record"

  @impl true
  def run(%{value: value}, %{observer: observer}) do
    send(Process.whereis(observer), :recovery_recorded)
    {:ok, %{value: value + 1}}
  end
end

defmodule Jido.Examples.Durability.ProcessRecovery.Block do
  use Jido.Action, name: "example_process_recovery_block"

  @impl true
  def run(%{value: value}, %{gate: gate, observer: observer}) do
    send(Process.whereis(observer), {:recovery_waiting, self()})

    receive do
      {:release_recovery, ^gate} -> {:ok, %{value: value + 1}}
    end
  end
end

defmodule Jido.Examples.Durability.ProcessRecovery do
  use Jido.Flow, name: "example_process_recovery"

  alias Jido.Examples.Durability.ProcessRecovery.{Block, Record}

  flow do
    step "record", action: Record, params: %{value: input(:value)}
    step "block", action: Block, params: %{value: result("record", :value)}
    output result("block")
  end
end
