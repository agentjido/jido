defmodule Jido.Flow.GraphTest do
  use ExUnit.Case, async: true

  alias Jido.Flow.{Graph, Ref}
  alias JidoActionTest.Fixtures.Actions.Add

  test "dependency levels use longest paths and names break ties" do
    components =
      components([
        {"z_root", []},
        {"a_root", []},
        {"z_middle", ["z_root"]},
        {"a_middle", ["a_root"]},
        {"a_final", ["z_root", "z_middle"]},
        {"z_final", ["a_middle", "z_middle"]}
      ])

    analysis = Graph.analyze(components)

    assert Map.take(analysis, [:levels, :remaining]) == %{
             levels: %{
               "z_root" => 0,
               "a_root" => 0,
               "z_middle" => 1,
               "a_middle" => 1,
               "a_final" => 2,
               "z_final" => 2
             },
             remaining: []
           }

    assert analysis.dependencies["a_final"] == ["z_middle", "z_root"]
    assert analysis.dependencies["z_final"] == ["a_middle", "z_middle"]
    assert analysis.terminals == ["a_final", "z_final"]

    assert Enum.map(analysis.ordered, &elem(&1, 0)) ==
             ["a_root", "z_root", "a_middle", "z_middle", "a_final", "z_final"]
  end

  test "reference and explicit dependencies on the same node count once" do
    components = components([{"root", []}, {"child", ["root", "root"]}])

    child = %{
      components["child"]
      | call: %{kind: :action, target: Add, params: %{value: Ref.result("root", :value)}}
    }

    analysis = Graph.analyze(Map.put(components, "child", child))

    assert Map.take(analysis, [:levels, :remaining]) == %{
             levels: %{"root" => 0, "child" => 1},
             remaining: []
           }

    assert analysis.dependencies == %{"root" => [], "child" => ["root"]}
    assert analysis.terminals == ["child"]
  end

  test "cycles retain all blocked nodes and partial levels from acyclic ancestors" do
    components =
      components([
        {"root", []},
        {"branch", ["root"]},
        {"one", ["two", "branch"]},
        {"two", ["one"]},
        {"blocked", ["one"]},
        {"self", ["self"]},
        {"self_child", ["self"]},
        {"independent", []}
      ])

    assert Map.take(Graph.analyze(components), [:levels, :remaining]) == %{
             levels: %{"root" => 0, "branch" => 1, "one" => 2, "independent" => 0},
             remaining: ["blocked", "one", "self", "self_child", "two"]
           }
  end

  test "missing dependencies block descendants without becoming components" do
    components = components([{"root", []}, {"child", ["missing", "root"]}, {"last", ["child"]}])

    assert Map.take(Graph.analyze(components), [:levels, :remaining]) == %{
             levels: %{"root" => 0, "child" => 1},
             remaining: ["child", "last"]
           }
  end

  test "empty graphs have no levels or blocked nodes" do
    assert Graph.analyze(%{}) == %{
             levels: %{},
             remaining: [],
             ordered: [],
             dependencies: %{},
             terminals: []
           }

    assert Graph.canonical_components(%{}) == []
  end

  defp components(edges) do
    Map.new(edges, fn {name, needs} ->
      {name,
       %{
         kind: :call,
         needs: needs,
         meta: %{},
         call: %{kind: :action, target: Add, params: %{}}
       }}
    end)
  end
end
