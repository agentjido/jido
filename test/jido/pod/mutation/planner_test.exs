defmodule JidoTest.Pod.Mutation.PlannerTest do
  use ExUnit.Case, async: true

  alias Jido.Pod.Mutation
  alias Jido.Pod.Mutation.Planner
  alias Jido.Pod.Topology

  defmodule Worker do
    @moduledoc false
    use Jido.Agent, name: "mutation_planner_worker", schema: []
  end

  defmodule NestedPod do
    @moduledoc false
    use Jido.Pod, name: "mutation_planner_nested_pod"
  end

  test "plans batched add mutations with mixed atom and string names" do
    topology = Topology.new!(name: "planner_mixed")

    ops = [
      Mutation.add_node(:planner, %{agent: Worker, manager: :planner_manager, activation: :eager}),
      Mutation.add_node(
        "reviewer",
        %{agent: Worker, manager: :reviewer_manager, activation: :lazy},
        owner: :planner,
        depends_on: [:planner]
      )
    ]

    assert {:ok, plan} = Planner.plan(topology, ops)
    assert plan.added == [:planner, "reviewer"]
    assert plan.removed == []
    assert plan.start_requested == [:planner]
    assert plan.start_waves == [[:planner]]

    assert {:ok, planner_node} = Topology.fetch_node(plan.final_topology, :planner)
    assert planner_node.activation == :eager
    assert Topology.owner_of(plan.final_topology, "reviewer") == {:ok, :planner}
    assert Topology.dependencies_of(plan.final_topology, "reviewer") == [:planner]
    assert plan.final_topology.version == 2
  end

  test "plans batched add mutations for nested pod nodes" do
    topology = Topology.new!(name: "planner_nested")

    ops = [
      Mutation.add_node("nested", %{
        module: NestedPod,
        manager: :nested_manager,
        kind: :pod,
        activation: :eager
      })
    ]

    assert {:ok, plan} = Planner.plan(topology, ops)
    assert plan.added == ["nested"]
    assert plan.start_requested == ["nested"]
    assert {:ok, nested_node} = Topology.fetch_node(plan.final_topology, "nested")
    assert nested_node.kind == :pod
  end

  test "plans remove mutations for owned subtrees" do
    topology =
      Topology.new!(
        name: "planner_remove",
        nodes: %{
          :planner => %{agent: Worker, manager: :planner_manager, activation: :eager},
          "reviewer" => %{agent: Worker, manager: :reviewer_manager, activation: :eager},
          "editor" => %{agent: Worker, manager: :editor_manager, activation: :lazy}
        },
        links: [
          {:owns, :planner, "reviewer"},
          {:owns, "reviewer", "editor"},
          {:depends_on, "editor", "reviewer"}
        ]
      )

    assert {:ok, plan} = Planner.plan(topology, [Mutation.remove_node("reviewer")])
    assert plan.added == []
    assert plan.removed == ["editor", "reviewer"]
    assert plan.stop_waves == [["editor"], ["reviewer"]]
    refute Map.has_key?(plan.final_topology.nodes, "reviewer")
    refute Map.has_key?(plan.final_topology.nodes, "editor")
    assert Map.has_key?(plan.final_topology.nodes, :planner)
  end

  test "rejects duplicate targets in the same batch" do
    topology = Topology.new!(name: "planner_duplicates")

    ops = [
      Mutation.add_node(:planner, %{agent: Worker, manager: :planner_manager}),
      Mutation.remove_node(:planner)
    ]

    assert {:error, error} = Planner.plan(topology, ops)
    assert Exception.message(error) =~ "cannot touch the same node more than once"
  end

  test "rejects add mutations for existing nodes" do
    topology =
      Topology.new!(
        name: "planner_existing",
        nodes: %{planner: %{agent: Worker, manager: :planner_manager}}
      )

    assert {:error, error} =
             Planner.plan(
               topology,
               [
                 Mutation.add_node(:planner, %{agent: Worker, manager: :alternate_manager},
                   owner: nil
                 )
               ]
             )

    assert Exception.message(error) =~ "already exists"
  end
end
