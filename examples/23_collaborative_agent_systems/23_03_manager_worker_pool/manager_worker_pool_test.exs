Code.require_file("manager_worker_pool.ex", __DIR__)

defmodule Jido.Examples.Collaboration.ManagerPoolTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.Examples.Collaboration.ManagerPool
  alias Jido.Examples.Collaboration.ManagerPool.{Manager, Worker}

  test "a manager reduces correlated results from a parallel worker pool" do
    jido = start_jido()
    manager_address = create(jido, "manager", Manager)
    worker_addresses = Enum.map(1..3, &create(jido, "worker-#{&1}", Worker))

    tasks = [
      %{task_id: "task-a", value: 2, fail: false},
      %{task_id: "task-b", value: 3, fail: true},
      %{task_id: "task-c", value: 5, fail: false}
    ]

    assert {:ok, state} =
             ManagerPool.run(jido, manager_address, worker_addresses, "mission-pool-1", tasks)

    assert state.expected == ["task-a", "task-b", "task-c"]

    assert state.results == [
             %{mission_id: "mission-pool-1", task_id: "task-a", status: :completed, value: 4},
             %{mission_id: "mission-pool-1", task_id: "task-b", status: :failed, value: nil},
             %{mission_id: "mission-pool-1", task_id: "task-c", status: :completed, value: 10}
           ]

    assert Jido.resident_agent_count(jido) == 4
  end

  defp create(jido, id, module) do
    {:ok, address} = Jido.agent_address(jido, id)
    {:ok, ^address} = Jido.create_agent(jido, address, module)
    address
  end

  defp start_jido do
    suffix = System.unique_integer([:positive])
    name = :"manager_pool_#{suffix}"
    persistence = {Jido.Persistence.ETS, table: Module.concat(__MODULE__, "Store#{suffix}")}

    start_supervised!(
      {Jido, name: name, namespace: "examples/manager-pool/#{suffix}", persistence: persistence},
      id: name
    )

    name
  end
end
