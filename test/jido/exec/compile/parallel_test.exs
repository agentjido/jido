defmodule Jido.Exec.Compile.ParallelTest do
  use ExUnit.Case, async: true

  alias Jido.Error
  alias Jido.Exec
  alias Jido.Exec.Node.Parallel
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias Jido.Test.Action.Fixtures.Actions.{Add, EchoParamsAction, Multiply}
  alias Runic.Workflow

  defmodule Effect do
    use Jido.Action, name: "compiled_parallel_effect"

    @impl true
    def run(%{name: name}, _context), do: {:ok, %{name: name}, [name]}
  end

  defmodule Fail do
    use Jido.Action, name: "compiled_parallel_fail"

    @impl true
    def run(_params, _context), do: {:error, "parallel failed"}
  end

  test "compile lowers one Parallel to one dedicated Runic Parallel component" do
    flow =
      parallel_flow("compiled_parallel_shape", [
        action("add", Add, %{value: Ref.input(:value), amount: 1}),
        action("multiply", Multiply, %{value: Ref.input(:value), amount: 2})
      ])

    assert {:ok, %Workflow{} = workflow} = Exec.compile(flow, [])

    assert %Parallel{name: "work", definition: %{kind: :parallel, actions: actions}} =
             parallel = Workflow.get_component(workflow, "work")

    assert Enum.map(actions, & &1.name) == ["add", "multiply"]
    assert [bindings: input_opts] = Runic.Component.inputs(parallel)
    assert input_opts[:type] == :any
    assert Keyword.keys(Runic.Component.outputs(parallel)) == [:value, :effects, :control]
    assert component_sources(workflow, "work") == ["__jido_input__/compiled_parallel_shape"]
  end

  test "Parallel keeps authored result and effect order" do
    flow =
      parallel_flow("compiled_parallel_order", [
        action("first", Effect, %{name: :first}),
        action("second", Effect, %{name: :second})
      ])

    assert compile_and_execute(flow, %{}) ==
             {:ok,
              %{
                work: [
                  %{name: "first", value: %{name: :first}},
                  %{name: "second", value: %{name: :second}}
                ]
              }, [:first, :second]}
  end

  test "Parallel collects named failures as ordered data" do
    flow =
      parallel_flow(
        "compiled_parallel_collect",
        [
          action("ok", EchoParamsAction, %{value: 1}),
          action("fail", Fail, %{})
        ],
        :collect_errors
      )

    assert {:ok,
            %{
              work: [
                %{name: "ok", status: :ok, value: %{value: 1}},
                %{name: "fail", status: :error, error: error}
              ]
            }} = compile_and_execute(flow, %{})

    assert error.type == :execution_error
    assert error.details.node == "work"
    assert error.details.action_index == 1
    assert error.details.action_name == "fail"
    refute Map.has_key?(error.details, :stacktrace)
  end

  test "Parallel fail-fast errors identify the selected Action" do
    flow =
      parallel_flow("compiled_parallel_fail_fast", [
        action("ok", EchoParamsAction, %{value: 1}),
        action("fail", Fail, %{})
      ])

    assert {:error, %Error.ExecutionError{} = error} = compile_and_execute(flow, %{})
    assert error.details.node == "work"
    assert error.details.node_path == ["work", "fail"]
    assert error.details.action_index == 1
    assert error.details.action_name == "fail"
  end

  test "a rebuilt Parallel keeps authored order" do
    flow =
      parallel_flow("compiled_parallel_rebuild", [
        action("first", EchoParamsAction, %{value: 1}),
        action("second", EchoParamsAction, %{value: 2})
      ])

    assert {:ok, workflow} = Exec.compile(flow, [])
    rebuilt = workflow |> Workflow.build_log() |> Workflow.from_log()

    assert execute(rebuilt, %{}) ==
             {:ok,
              %{
                work: [
                  %{name: "first", value: %{value: 1}},
                  %{name: "second", value: %{value: 2}}
                ]
              }}
  end

  defp parallel_flow(name, actions, on_error \\ :fail_fast) do
    Flow.new!(%{
      name: name,
      components: [%{kind: :parallel, name: "work", actions: actions, on_error: on_error}],
      output: %{work: Ref.result("work")}
    })
  end

  defp action(name, target, params), do: %{name: name, action: target, params: params}

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
