defmodule Jido.Exec.Compile.IterateTest do
  use ExUnit.Case, async: true

  alias Jido.Error
  alias Jido.Exec
  alias Jido.Exec.Node.Iterate
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias Runic.Workflow

  defmodule Increment do
    use Jido.Action, name: "compiled_iterate_increment"
    def run(%{count: count}, _context), do: {:ok, %{count: count + 1}, [count]}
  end

  test "compile lowers one Iterate to one dedicated Runic Iterate component" do
    assert {:ok, %Workflow{} = workflow} = Exec.compile(iterate_flow("compiled_iterate_shape", 3), [])

    assert %Iterate{name: "count", definition: %{kind: :iterate}} =
             iterate = Workflow.get_component(workflow, "count")

    assert [bindings: input_opts] = Runic.Component.inputs(iterate)
    assert input_opts[:type] == :any
    assert Keyword.keys(Runic.Component.outputs(iterate)) == [:value, :effects, :control]
  end

  test "Iterate replaces state until its completion expression is true" do
    assert Exec.run(iterate_flow("compiled_iterate_execution", 3)) ==
             {:ok,
              %{
                kind: :jido_flow_iterate_result,
                iterations: 3,
                state: %{count: 3},
                output: %{count: 3}
              }, [0, 1, 2]}
  end

  test "Iterate can complete before it runs its Action" do
    assert Exec.run(iterate_flow("compiled_iterate_zero", 0)) ==
             {:ok,
              %{
                kind: :jido_flow_iterate_result,
                iterations: 0,
                state: %{count: 0},
                output: nil
              }}
  end

  test "Iterate reports maximum iteration exhaustion" do
    flow = iterate_flow("compiled_iterate_exhaustion", 3, 2)

    assert {:error, %Error.ExecutionError{} = error} = Exec.run(flow)
    assert error.phase == :iterate_exhaustion
    assert error.details.completed_iterations == 2
  end

  test "a rebuilt Iterate keeps state replacement and effect order" do
    assert {:ok, workflow} = Exec.compile(iterate_flow("compiled_iterate_rebuild", 2), [])
    rebuilt = workflow |> Workflow.build_log() |> Workflow.from_log()
    {rebuilt, observation} = Workflow.execute(rebuilt, %{})

    assert Exec.result(rebuilt, observation) ==
             {:ok,
              %{
                kind: :jido_flow_iterate_result,
                iterations: 2,
                state: %{count: 2},
                output: %{count: 2}
              }, [0, 1]}
  end

  defp iterate_flow(name, limit, max_iterations \\ 5) do
    Flow.new!(%{
      name: name,
      components: [
        %{
          kind: :iterate,
          name: "count",
          action: Increment,
          params: %{count: Ref.state(:count)},
          state: %{initial: %{count: 0}, update: %{count: Ref.body_result(:count)}},
          completion: Jido.Expr.new!(:>=, [Ref.state(:count), limit]),
          max_iterations: max_iterations
        }
      ],
      output: Ref.result("count")
    })
  end
end
