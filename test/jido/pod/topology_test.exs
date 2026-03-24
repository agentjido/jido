defmodule JidoTest.Pod.TopologyTest do
  use ExUnit.Case, async: true

  alias Jido.Pod.Topology
  alias Jido.Pod.Topology.Link

  defmodule WorkerAgent do
    @moduledoc false
    use Jido.Agent, name: "pod_topology_worker"
  end

  test "normalizes tuple shorthand links into canonical link structs" do
    assert {:ok, %Topology{} = topology} =
             Topology.new(
               name: "editorial_pipeline",
               nodes: %{
                 planner: %{agent: WorkerAgent, manager: :planner_members},
                 reviewer: %{agent: WorkerAgent, manager: :reviewer_members},
                 publisher: %{agent: WorkerAgent, manager: :publisher_members}
               },
               links: [
                 {:depends_on, :reviewer, :planner},
                 {:depends_on, :reviewer, :planner},
                 {:owns, :planner, :publisher, %{role: :lead}}
               ]
             )

    assert [
             %Link{type: :depends_on, from: :reviewer, to: :planner, meta: %{}},
             %Link{type: :owns, from: :planner, to: :publisher, meta: %{role: :lead}}
           ] = topology.links
  end

  test "rejects invalid endpoints and self-links" do
    assert {:error, reason} =
             Topology.new(
               name: "broken",
               nodes: %{
                 planner: %{agent: WorkerAgent, manager: :planner_members}
               },
               links: [{:depends_on, :reviewer, :planner}]
             )

    assert inspect(reason) =~ "source node does not exist"

    assert {:error, reason} = Link.new({:depends_on, :planner, :planner})
    assert inspect(reason) =~ "cannot point to the same node"
  end

  test "delete_node removes incident links" do
    topology =
      Topology.new!(
        name: "mutable",
        nodes: %{
          planner: %{agent: WorkerAgent, manager: :planner_members},
          reviewer: %{agent: WorkerAgent, manager: :reviewer_members}
        },
        links: [{:depends_on, :reviewer, :planner}]
      )

    updated = Topology.delete_node(topology, :planner)

    refute Map.has_key?(updated.nodes, :planner)
    assert [] == updated.links
  end

  test "dependency_order honors depends_on links" do
    topology =
      Topology.new!(
        name: "ordered",
        nodes: %{
          planner: %{agent: WorkerAgent, manager: :planner_members},
          reviewer: %{agent: WorkerAgent, manager: :reviewer_members},
          publisher: %{agent: WorkerAgent, manager: :publisher_members},
          auditor: %{agent: WorkerAgent, manager: :auditor_members}
        },
        links: [
          {:depends_on, :reviewer, :planner},
          {:depends_on, :publisher, :reviewer}
        ]
      )

    assert {:ok, ordered} =
             Topology.dependency_order(topology, [:publisher, :auditor, :reviewer, :planner])

    assert ordered == [:auditor, :planner, :reviewer, :publisher]
  end

  test "dependency_order rejects cycles" do
    topology =
      Topology.new!(
        name: "cyclic",
        nodes: %{
          planner: %{agent: WorkerAgent, manager: :planner_members},
          reviewer: %{agent: WorkerAgent, manager: :reviewer_members}
        },
        links: [
          {:depends_on, :reviewer, :planner},
          {:depends_on, :planner, :reviewer}
        ]
      )

    assert {:error, reason} = Topology.dependency_order(topology, [:reviewer, :planner])
    assert inspect(reason) =~ "cyclic"
  end

  test "put_link validates endpoints and deduplicates" do
    topology =
      Topology.from_nodes!("link_validation", %{
        planner: %{agent: WorkerAgent, manager: :planner_members},
        reviewer: %{agent: WorkerAgent, manager: :reviewer_members}
      })

    assert {:ok, topology} = Topology.put_link(topology, {:depends_on, :reviewer, :planner})
    assert {:ok, same_topology} = Topology.put_link(topology, {:depends_on, :reviewer, :planner})
    assert topology == same_topology

    assert {:error, reason} = Topology.put_link(topology, {:owns, :reviewer, :publisher})
    assert inspect(reason) =~ "target node does not exist"
  end
end
