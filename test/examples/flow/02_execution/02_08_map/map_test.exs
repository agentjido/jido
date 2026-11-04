Code.require_file("../../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Execution.MapTest do
  use ExUnit.Case, async: false
  @moduletag :example
  setup_all do
    JidoTest.Examples.Loader.require_source!("flow/02_execution/02_08_map/map.ex")
    :ok
  end

  test "keeps outcomes in order and uses deterministic concurrency barriers" do
    module = Jido.Examples.Execution.Map
    assert {:ok, %{items: [first, second, third]}} = Jido.Exec.run(module, %{values: [3, -1, 2]})
    assert first == %{status: :ok, value: %{index: 0, value: 6}}
    assert second.status == :error
    assert third == %{status: :ok, value: %{index: 2, value: 4}}

    gate = make_ref()
    parent = self()

    task =
      Task.async(fn ->
        Jido.Exec.run(module, %{values: [1, 2, 3]}, %{observer: parent, gate: gate}, max_concurrency: 2)
      end)

    assert_receive {:map_item_ready, _, first_worker}
    assert_receive {:map_item_ready, _, second_worker}
    refute_received {:map_item_ready, _, _}
    send(first_worker, {:release_map_item, gate})
    send(second_worker, {:release_map_item, gate})
    assert_receive {:map_item_ready, _, third_worker}
    send(third_worker, {:release_map_item, gate})
    assert {:ok, %{items: outcomes}} = Task.await(task)
    assert Enum.map(outcomes, & &1.value.index) == [0, 1, 2]
  end
end
