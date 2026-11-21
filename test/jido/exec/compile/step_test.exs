defmodule Jido.Exec.Compile.StepTest do
  use ExUnit.Case, async: true

  alias Jido.Error
  alias Jido.Exec
  alias Jido.Exec.Node.Action
  alias Jido.Flow
  alias Jido.Flow.Ref

  alias Jido.Test.Action.Fixtures.Actions.{
    Add,
    ContextEcho,
    ErrorAction,
    ExtrasAction,
    InvalidOutput
  }

  alias Runic.Workflow

  defmodule Continue do
    use Jido.Action, name: "compiled_step_continue"

    @impl true
    def run(params, _context), do: {:continue, params, Add}
  end

  defmodule InvalidEffects do
    use Jido.Action, name: "compiled_step_invalid_effects"

    @impl true
    def run(_params, _context), do: {:ok, %{ok: true}, [:effect | :invalid_tail]}
  end

  test "compile lowers one Step to one dedicated Runic Action component" do
    flow = step_flow("compiled_step_shape", Add, %{value: Ref.input(:value), amount: 2})

    assert {:ok, %Workflow{} = workflow} = Exec.compile(flow, [])

    assert %Action{
             name: "step",
             call: %{kind: :action, target: Add}
           } = action = Workflow.get_component(workflow, "step")

    assert [bindings: input_opts] = Runic.Component.inputs(action)
    assert input_opts[:type] == :any
    assert Keyword.keys(Runic.Component.outputs(action)) == [:value, :effects, :control]
    assert component_sources(workflow, "step") == ["__jido_input__/compiled_step_shape"]

    output =
      workflow
      |> Workflow.components()
      |> Map.values()
      |> Enum.find(&is_struct(&1, Jido.Exec.Node.Output))

    assert Enum.sort(component_sources(workflow, output.name)) ==
             ["__jido_input__/compiled_step_shape", "step"]
  end

  test "the compiled Step resolves Flow input and executes through Runic" do
    flow = step_flow("compiled_step_input", Add, %{value: Ref.input(:value), amount: 3})

    assert compile_and_execute(flow, %{value: 4}) == {:ok, %{value: 7}}
  end

  test "the compiled Step receives caller context" do
    flow = step_flow("compiled_step_context", ContextEcho, %{value: Ref.input(:value)})

    assert {:ok, workflow} = Exec.compile(flow, [])

    {workflow, observation} =
      workflow
      |> Workflow.put_run_context(%{_global: %{trace_id: "trace-7"}})
      |> Workflow.execute(%{value: 7})

    assert Exec.result(workflow, observation) ==
             {:ok, %{value: 7, trace_id: "trace-7"}}
  end

  test "the compiled Step preserves Action effects" do
    flow = step_flow("compiled_step_effects", ExtrasAction, %{value: Ref.input(:value)})

    assert {:ok, workflow} = Exec.compile(flow, [])

    {workflow, observation} =
      workflow
      |> Workflow.put_run_context(%{_global: %{trace_id: "effect-8"}})
      |> Workflow.execute(%{value: 8})

    assert Exec.result(workflow, observation) ==
             {:ok, %{value: 8}, [%{trace_id: "effect-8"}]}
  end

  test "a missing input reference fails at the Step boundary" do
    flow = step_flow("compiled_step_missing_ref", Add, %{value: Ref.input(:missing), amount: 1})

    assert {:error, %Error.ExecutionError{} = error} = compile_and_execute(flow, %{})
    assert error.details.reason == :missing_key
    assert error.details.node == "step"
    assert error.details.node_path == ["step"]
  end

  test "Action input validation failure keeps the Step source path" do
    flow = step_flow("compiled_step_input_validation", Add, %{value: Ref.input(:value), amount: 1})

    assert {:error, %Error.ValidationError{} = error} =
             compile_and_execute(flow, %{value: "invalid"})

    assert error.details.node == "step"
    assert error.details.node_path == ["step"]
  end

  test "Action output validation failure keeps the Step source path" do
    flow = step_flow("compiled_step_output_validation", InvalidOutput, %{value: Ref.input(:value)})

    assert {:error, %Error.ValidationError{} = error} = compile_and_execute(flow, %{value: 3})
    assert error.details.node == "step"
    assert error.details.node_path == ["step"]
  end

  test "an Action exception becomes an execution error without escaping Runic" do
    flow = step_flow("compiled_step_action_exception", ErrorAction, %{error_type: :runtime})

    assert {:error, %Error.ExecutionError{} = error} = compile_and_execute(flow, %{})
    assert error.message == "Runtime error"
    assert error.details.exception == RuntimeError
    assert error.details.node == "step"
    assert error.details.node_path == ["step"]
  end

  test "a Step rejects Action continuation control" do
    flow = step_flow("compiled_step_continuation", Continue, %{value: Ref.input(:value)})

    assert {:error, %Error.ExecutionError{} = error} = compile_and_execute(flow, %{value: 1})
    assert error.details.reason == :unsupported_continuation
    assert error.details.node == "step"
    assert error.details.node_path == ["step"]
  end

  test "a Step rejects an improper effects list" do
    flow = step_flow("compiled_step_invalid_effects", InvalidEffects, %{})

    assert {:error, %Error.ExecutionError{} = error} = compile_and_execute(flow, %{})
    assert error.message == "Action returned an invalid effects list"
    assert error.details.node == "step"
    assert error.details.node_path == ["step"]
  end

  defp step_flow(name, action, params) do
    Flow.new!(%{
      name: name,
      components: [%{kind: :step, name: "step", action: action, params: params}],
      output: Ref.result("step")
    })
  end

  defp compile_and_execute(flow, input) do
    assert {:ok, workflow} = Exec.compile(flow, [])
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
