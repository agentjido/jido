defmodule Jido.Exec.Compile.ReduceTest do
  use ExUnit.Case, async: true

  alias Jido.Error
  alias Jido.Exec
  alias Jido.Exec.Node.Reduce
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias Runic.Workflow

  defmodule Sum do
    use Jido.Action, name: "compiled_reduce_sum"

    @impl true
    def run(%{accumulator: accumulator, item: item}, _context) do
      {:ok, %{total: accumulator.total + item}, [item]}
    end
  end

  defmodule Coordinates do
    use Jido.Action, name: "compiled_reduce_coordinates"

    @impl true
    def run(%{accumulator: accumulator, item: item, index: index, id: id}, _context) do
      {:ok, %{items: accumulator.items ++ [%{item: item, index: index, id: id}]}}
    end
  end

  defmodule FailNegative do
    use Jido.Action, name: "compiled_reduce_fail_negative"

    @impl true
    def run(%{item: item}, _context) when item < 0, do: {:error, "negative item"}
    def run(%{accumulator: accumulator, item: item}, _context), do: {:ok, %{total: accumulator.total + item}}
  end

  test "compile lowers one Reduce to one dedicated Runic Reduce component" do
    flow = reduce_flow("compiled_reduce_shape", Ref.input(:items), %{total: 0}, Sum)

    assert {:ok, %Workflow{} = workflow} = Exec.compile(flow, [])

    assert %Reduce{name: "sum", definition: %{kind: :reduce}} =
             reduce = Workflow.get_component(workflow, "sum")

    assert [bindings: input_opts] = Runic.Component.inputs(reduce)
    assert input_opts[:type] == :any
    assert Keyword.keys(Runic.Component.outputs(reduce)) == [:value, :effects, :control]
    assert component_sources(workflow, "sum") == ["__jido_input__/compiled_reduce_shape"]
  end

  test "Reduce runs serially and preserves effect order" do
    flow = reduce_flow("compiled_reduce_order", [3, 1, 2], %{total: 0}, Sum)

    assert compile_and_execute(flow, %{}) ==
             {:ok, %{result: %{total: 6}}, [3, 1, 2]}
  end

  test "Reduce exposes ordered item coordinates" do
    flow =
      reduce_flow(
        "compiled_reduce_coordinates",
        [:a, :b],
        %{items: []},
        Coordinates,
        %{
          accumulator: Ref.accumulator(),
          item: Ref.item(),
          index: Ref.item_index(),
          id: Ref.item_id()
        }
      )

    assert {:ok, %{result: %{items: [first, second]}}} = compile_and_execute(flow, %{})
    assert first.item == :a
    assert first.index == 0
    assert second.item == :b
    assert second.index == 1
    assert is_binary(first.id)
    assert is_binary(second.id)
    refute first.id == second.id
  end

  test "Reduce failures identify the failed item" do
    flow = reduce_flow("compiled_reduce_failure", [1, -1, 2], %{total: 0}, FailNegative)

    assert {:error, %Error.ExecutionError{} = error} = compile_and_execute(flow, %{})
    assert error.details.node == "sum"
    assert error.details.item_index == 1
    assert is_binary(error.details.item_id)
  end

  test "Reduce rejects invalid collections and initial values" do
    collection = reduce_flow("compiled_reduce_collection", Ref.input(:items), %{total: 0}, Sum)

    assert {:error, %Error.ExecutionError{message: "Reduce collection is not enumerable"}} =
             compile_and_execute(collection, %{items: 1})

    initial = reduce_flow("compiled_reduce_initial", [1], Ref.input(:initial), Sum)

    assert {:error, %Error.ExecutionError{message: "reduce initial value must be a map or Jido.Action.Output"}} =
             compile_and_execute(initial, %{initial: 1})
  end

  test "Reduce returns its initial value for an empty collection" do
    flow = reduce_flow("compiled_reduce_empty", [], %{total: 7}, Sum)

    assert compile_and_execute(flow, %{}) == {:ok, %{result: %{total: 7}}}
  end

  test "a rebuilt Reduce preserves serial accumulation" do
    flow = reduce_flow("compiled_reduce_rebuild", [1, 2, 3], %{total: 0}, Sum)

    assert {:ok, workflow} = Exec.compile(flow, [])
    rebuilt = workflow |> Workflow.build_log() |> Workflow.from_log()

    assert execute(rebuilt, %{}) == {:ok, %{result: %{total: 6}}, [1, 2, 3]}
  end

  defp reduce_flow(name, collection, initial, action, params \\ nil) do
    params = params || %{accumulator: Ref.accumulator(), item: Ref.item()}

    Flow.new!(%{
      name: name,
      components: [
        %{
          kind: :reduce,
          name: "sum",
          collection: collection,
          initial: initial,
          action: action,
          params: params
        }
      ],
      output: %{result: Ref.result("sum")}
    })
  end

  defp compile_and_execute(flow, input) do
    assert {:ok, workflow} = Exec.compile(flow, [])
    execute(workflow, input)
  end

  defp execute(workflow, input) do
    {workflow, observation} = Workflow.execute(workflow, input)
    Exec.result(workflow, observation)
  end

  defp component_sources(workflow, name) do
    graph = Workflow.component_graph(workflow)
    component = Workflow.get_component!(workflow, name)

    graph
    |> Multigraph.in_neighbors(component)
    |> Enum.map(& &1.name)
  end
end
