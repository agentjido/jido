Code.require_file("../support/jido_flow/flow_edges.ex", __DIR__)

defmodule Jido.Flow.Authoring.FlowEdgesTest do
  use ExUnit.Case, async: false
  @moduletag :authoring

  alias Jido.Test.Flow.Authoring.FlowEdges.{Dependencies, Parent, Routing}

  test "result references and needs control work, not declaration order or Action input" do
    assert {:ok, dependencies} = Jido.Flow.dependencies(Dependencies.flow())

    assert dependencies["join"] == %{
             needs: ["audit"],
             references: ["left", "right"],
             effective: ["audit", "left", "right"]
           }

    ref = make_ref()

    assert {:ok, %{total: 7, input_keys: [:left, :right]}} =
             Jido.Exec.run(
               Dependencies,
               %{left: 3, right: 4, audit: 0},
               %{observer: self(), run_ref: ref}
             )

    events = for _ <- 1..4, do: receive_event(ref)
    assert Enum.sort(events) == [:audit, :join, :left, :right]
    assert List.last(events) == :join
    refute_received {^ref, _}
  end

  test "Choice has static branch dependencies and does not use fallback after a selected failure" do
    assert {:ok, dependencies} = Jido.Flow.dependencies(Routing.flow())
    assert dependencies["route"].references == ["unused_route_data"]

    assert_route(%{score: 100, fail: false, value: 7}, :urgent)
    assert_route(%{score: 10, fail: false, value: 7}, :standard)

    ref = make_ref()

    assert {:error, %Jido.Error.ExecutionError{}} =
             Jido.Exec.run(
               Routing,
               %{score: 10, fail: true, value: 7},
               %{observer: self(), run_ref: ref}
             )

    assert [receive_event(ref), receive_event(ref)] == [:unused_route_data, :failed_route]
    refute_received {^ref, _}
  end

  test "a child Flow receives context and reports input and leaf errors at their boundaries" do
    assert {:ok, %{child: %{value: 3, label: "shared"}}} =
             Jido.Exec.run(Parent, %{value: 2}, %{label: "shared"})

    assert {:error, input_error} = Jido.Exec.run(Parent, %{value: "bad"}, %{label: "shared"})
    assert input_error.details.node_path == ["child"]
    assert input_error.details.phase == :subflow_input

    assert {:error, leaf_error} = Jido.Exec.run(Parent, %{value: -1}, %{label: "shared"})
    assert leaf_error.details.node_path == ["child", "compute"]
  end

  defp assert_route(input, expected) do
    ref = make_ref()

    assert {:ok, %{route: ^expected, value: 7}} =
             Jido.Exec.run(Routing, input, %{observer: self(), run_ref: ref})

    assert [receive_event(ref), receive_event(ref)] == [:unused_route_data, expected]
    refute_received {^ref, _}
  end

  defp receive_event(ref) do
    assert_receive {^ref, event}
    event
  end
end
