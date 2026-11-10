defmodule Jido.Examples.Durability.SnapshotAndResume.Record do
  use Jido.Action, name: "example_snapshot_record"

  @impl true
  def run(%{step: step, value: value}, %{observer: observer}) do
    send(Process.whereis(observer), {:snapshot_step, step})
    {:ok, %{value: value + 1}}
  end
end

defmodule Jido.Examples.Durability.SnapshotAndResume do
  use Jido.Flow, name: "example_snapshot_and_resume"

  alias Jido.Examples.Durability.SnapshotAndResume.Record

  flow do
    step "first", action: Record, params: %{step: 1, value: input(:value)}
    step "second", action: Record, params: %{step: 2, value: result("first", :value)}
    output result("second")
  end
end
