defmodule Jido.Flow.GraphTest do
  use ExUnit.Case, async: true

  alias Jido.Flow
  alias Jido.Flow.{Graph, Ref}

  defmodule Echo do
    use Jido.Action, name: "flow_graph_echo"

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule Authored do
    use Jido.Flow, name: "ready_flow"

    flow do
      step("echo", action: Echo, params: %{})
      output(result("echo"))
    end
  end

  test "builds one shallow graph over named forms" do
    flow =
      Flow.new!(%{
        name: "shallow_graph",
        forms: %{
          load: Echo,
          each: %{
            type: :map,
            collection: Ref.result(:load, :items),
            action: Echo,
            params: %{value: Ref.item()}
          },
          audit: Echo
        },
        needs: %{each: [:audit]},
        output: Ref.result(:each)
      })

    assert %Graph{} = flow.graph
    assert Map.keys(flow.graph.dependencies) == ["audit", "each", "load"]
    assert flow.graph.dependencies["audit"] == %{data: [], control: []}
    assert flow.graph.dependencies["load"] == %{data: [], control: []}

    assert flow.graph.dependencies["each"] == %{
             data: ["load"],
             control: ["audit"]
           }

    assert Map.keys(Map.from_struct(flow.graph)) == [:dependencies]
    refute function_exported?(Graph, :ready, 2)
    refute Code.ensure_loaded?(Jido.Flow.Dependency)
    refute Enum.any?(Map.keys(flow.graph.dependencies), &match?({_, _}, &1))
    assert is_map(flow.identity)
    assert flow.identity == Flow.semantic_identity(flow) |> elem(1)
  end

  test "uses the canonical Flow as the only Flow program" do
    refute function_exported?(Flow, :compile, 1)
    refute function_exported?(Flow, :compile!, 1)
    refute function_exported?(Authored, :__jido_compiled__, 0)
    refute Code.ensure_loaded?(Jido.Flow.Compiler)
    refute Code.ensure_loaded?(Jido.Flow.Compiler.Fragment)
    refute Code.ensure_loaded?(Jido.Flow.Compiled)
    refute Code.ensure_loaded?(Jido.Flow.Compiled.Statement)
    refute Code.ensure_loaded?(Jido.Flow.Identity)
    refute Code.ensure_loaded?(Jido.Flow.Extensions)
    refute Code.ensure_loaded?(Jido.Flow.Extensions.Builtin)
    refute Code.ensure_loaded?(Jido.Flow.Extension)

    for form <- [
          Jido.Flow.Form.Map,
          Jido.Flow.Form.Reduce,
          Jido.Flow.Form.Choice,
          Jido.Flow.Form.Parallel,
          Jido.Flow.Form.Iterate,
          Jido.Flow.Form.Wait
        ] do
      assert Code.ensure_loaded?(form)
    end
  end

  test "cycle errors contain only forms that are in a cycle" do
    assert {:error, error} =
             Flow.new(%{
               name: "exact_cycle_members",
               forms: %{a: Echo, b: Echo, downstream: Echo, self: Echo},
               needs: %{
                 a: [:b],
                 b: [:a],
                 downstream: [:b],
                 self: [:self]
               },
               output: Ref.result(:downstream)
             })

    assert error.details.reason == :cycle
    assert error.details.forms == ["a", "b", "self"]
  end
end
