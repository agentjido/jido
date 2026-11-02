defmodule Jido.Exec.Test.WaitStoreTest do
  use ExUnit.Case, async: true
  alias Jido.Exec.Test.WaitHost, as: Waits
  alias Jido.Exec.Test.WaitStore.Memory

  defmodule SelectionFlow do
    use Jido.Flow, name: "stored_selection"

    flow do
      selection "decision" do
        await "approved", event: "approved", match: %{id: input(:id)}
        timer "expired", after_ms: 10
      end

      output result("decision")
    end
  end

  test "a lost save reply cannot select or consume input twice" do
    store = Memory.new()
    on_exit(fn -> if :ets.info(store) != :undefined, do: :ets.delete(store) end)
    {:ok, workflow} = Waits.start("stored", SelectionFlow, %{id: 1}, %{}, now: 0)
    assert {:ok, 1} = Memory.save("stored", 0, workflow, store)
    assert {:ok, 1} = Memory.save("stored", 0, workflow, store)
    assert {:ok, 1, workflow} = Memory.load("stored", store)
    {:waiting, [request]} = Waits.status(workflow)
    input = %{id: "approved-1", event: "approved", wait_id: request.id, payload: %{id: 1}}
    assert {:ok, completed} = Waits.accept(workflow, input, %{}, now: 1)
    assert {:ok, 2} = Memory.save("stored", 1, completed, store)
    assert {:ok, 2} = Memory.save("stored", 1, completed, store)
    assert {:ok, 2, restored} = Memory.load("stored", store)
    assert {:ok, ^restored} = Waits.accept(restored, input, %{}, now: 2)
    assert {:complete, {:ok, %{selected: "approved"}}} = Waits.status(restored)
    assert {:error, :conflict} = Memory.save("stored", 0, workflow, store)
    assert {:ok, cancelled} = Waits.cancel(workflow)
    assert {:error, :conflict} = Memory.save("stored", 1, cancelled, store)
  end

  test "competing transitions have only one accepted revision" do
    store = Memory.new()
    {:ok, workflow} = Waits.start("race", SelectionFlow, %{id: 1}, %{}, now: 0)
    assert {:ok, 1} = Memory.save("race", 0, workflow, store)
    {:waiting, [request]} = Waits.status(workflow)

    {:ok, accepted} =
      Waits.accept(
        workflow,
        %{id: "event", event: "approved", wait_id: request.id, payload: %{id: 1}},
        %{},
        now: 1
      )

    {:ok, cancelled} = Waits.cancel(workflow)

    tasks =
      for candidate <- [accepted, cancelled],
          do: Task.async(fn -> Memory.save("race", 1, candidate, store) end)

    results = Enum.map(tasks, &Task.await/1)
    assert Enum.sort(results) == Enum.sort([{:ok, 2}, {:error, :conflict}])
    assert {:ok, 2, _} = Memory.load("race", store)
    assert {:error, :not_found} = Memory.load("missing", store)
    assert Memory.close(store)
  end
end
