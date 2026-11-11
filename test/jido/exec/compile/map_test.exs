defmodule Jido.Exec.Compile.MapTest do
  use ExUnit.Case, async: true

  @moduletag obligation: "jido_action.boundary.I7"

  alias Jido.Error
  alias Jido.Exec
  alias Jido.Exec.Node.Output
  alias Jido.Exec.Node.Map, as: MapNode
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias Jido.Test.Action.Fixtures.Actions.EchoParamsAction
  alias Runic.Workflow

  defmodule Effect do
    use Jido.Action, name: "compiled_map_effect"

    @impl true
    def run(%{item: item}, _context), do: {:ok, %{item: item}, [item]}
  end

  defmodule FailNegative do
    use Jido.Action, name: "compiled_map_fail_negative"

    @impl true
    def run(%{item: item}, _context) when item < 0,
      do: {:error, Error.execution_error("negative item", %{retry: false})}

    def run(%{item: item}, _context), do: {:ok, %{item: item}, [item]}
  end

  test "compile lowers one Map to one dedicated Runic Map component" do
    flow = map_flow("compiled_map_shape", Ref.input(:items), EchoParamsAction, %{item: Ref.item()})

    assert {:ok, %Workflow{} = workflow} = Exec.compile(flow, [])

    assert %MapNode{name: "items", definition: %{kind: :map}} =
             map = Workflow.get_component(workflow, "items")

    assert [bindings: input_opts] = Runic.Component.inputs(map)
    assert input_opts[:type] == :any
    assert Keyword.keys(Runic.Component.outputs(map)) == [:value, :effects, :control]
    assert component_sources(workflow, "items") == ["__jido_input__/compiled_map_shape"]

    output = workflow |> Workflow.components() |> Map.values() |> Enum.find(&is_struct(&1, Output))

    assert Enum.sort(component_sources(workflow, output.name)) ==
             ["__jido_input__/compiled_map_shape", "items"]
  end

  test "Map preserves item order and exposes item coordinates" do
    flow =
      map_flow("compiled_map_items", Ref.input(:items), EchoParamsAction, %{
        item: Ref.item(),
        index: Ref.item_index(),
        id: Ref.item_id()
      })

    assert {:ok, %{items: [first, second]} = first_result} =
             compile_and_execute(flow, %{items: [:a, :a]})

    assert first.item == :a
    assert first.index == 0
    assert second.item == :a
    assert second.index == 1
    assert is_binary(first.id)
    assert is_binary(second.id)
    refute first.id == second.id

    assert compile_and_execute(flow, %{items: [:a, :a]}) == {:ok, first_result}
  end

  test "Map preserves effects in item order" do
    flow = map_flow("compiled_map_effects", [3, 1, 2], Effect, %{item: Ref.item()})

    assert compile_and_execute(flow, %{}) ==
             {:ok, %{items: [%{item: 3}, %{item: 1}, %{item: 2}]}, [3, 1, 2]}
  end

  test "Map collect-errors keeps ordered values and omits failed effects" do
    flow =
      map_flow(
        "compiled_map_collect",
        [1, -1, 2],
        FailNegative,
        %{item: Ref.item()},
        :collect_errors
      )

    assert {:ok,
            %{
              items: [
                %{status: :ok, value: %{item: 1}},
                %{status: :error, error: error},
                %{status: :ok, value: %{item: 2}}
              ]
            }, [1, 2]} = compile_and_execute(flow, %{})

    assert error.type == :execution_error
    assert error.details.node == "items"
    assert error.details.target == FailNegative
    assert error.details.item_index == 1
    assert is_binary(error.details.item_id)
    refute error.details.retry
    refute Map.has_key?(error.details, :stacktrace)
  end

  test "Map collection keeps reference failures separate from item identity" do
    flow =
      map_flow(
        "compiled_map_reference_error",
        [%{}],
        EchoParamsAction,
        %{value: Ref.item(:missing)},
        :collect_errors
      )

    assert {:ok, %{items: [%{status: :error, error: error}]}} = compile_and_execute(flow, %{})
    assert error.details.reason == :missing_key
    refute Map.has_key?(error.details, :item_index)
    refute Map.has_key?(error.details, :item_id)
  end

  test "Map fail-fast errors identify the failed item" do
    flow = map_flow("compiled_map_fail_fast", [1, -1, 2], FailNegative, %{item: Ref.item()})

    assert {:error, %Error.ExecutionError{} = error} = compile_and_execute(flow, %{})
    assert error.details.node == "items"
    assert error.details.item_index == 1
    assert is_binary(error.details.item_id)
  end

  test "Map rejects a non-enumerable collection" do
    flow = map_flow("compiled_map_collection", Ref.input(:items), EchoParamsAction, %{item: Ref.item()})

    assert {:error, %Error.ExecutionError{} = error} = compile_and_execute(flow, %{items: 1})
    assert error.message == "Map collection is not enumerable"
    assert error.details.node == "items"
    assert error.phase == :map_collection
  end

  test "a rebuilt Map keeps item order" do
    flow = map_flow("compiled_map_rebuild", [:a, :b], EchoParamsAction, %{item: Ref.item()})

    assert {:ok, workflow} = Exec.compile(flow, [])
    rebuilt = workflow |> Workflow.build_log() |> Workflow.from_log()

    assert execute(rebuilt, %{}) == {:ok, %{items: [%{item: :a}, %{item: :b}]}}
  end

  defp map_flow(name, collection, action, params, on_error \\ :fail_fast) do
    Flow.new!(%{
      name: name,
      components: [
        %{
          kind: :map,
          name: "items",
          collection: collection,
          action: action,
          params: params,
          on_error: on_error
        }
      ],
      output: %{items: Ref.result("items")}
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
