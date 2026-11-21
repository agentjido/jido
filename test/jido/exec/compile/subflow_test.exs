defmodule Jido.Exec.Compile.SubflowTest do
  use ExUnit.Case, async: true

  alias Jido.Exec
  alias Jido.Exec.Node.Subflow
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias Runic.Workflow

  defmodule ChildAction do
    use Jido.Action, name: "compiled_subflow_action"

    @impl true
    def run(%{value: value}, context) do
      {:ok, %{value: value + 1, trace_id: context.trace_id}, [:child_effect]}
    end
  end

  defmodule Child do
    use Jido.Flow, name: "compiled_subflow_child"

    flow do
      step "work", action: ChildAction, params: %{value: input(:value)}
      output result("work")
    end
  end

  test "compile lowers one Subflow to one dedicated Runic Subflow component" do
    flow = parent_flow("compiled_subflow_shape")

    assert {:ok, %Workflow{} = workflow} = Exec.compile(flow, [])

    assert %Subflow{
             name: "child",
             definition: %{kind: :call, call: %{kind: :flow, target: Child}},
             child_workflow: %Workflow{}
           } = subflow = Workflow.get_component(workflow, "child")

    assert [bindings: input_opts] = Runic.Component.inputs(subflow)
    assert input_opts[:type] == :any
    assert Keyword.keys(Runic.Component.outputs(subflow)) == [:value, :effects, :control]
  end

  test "Subflow passes parameters and context and returns child effects" do
    flow = parent_flow("compiled_subflow_execution")

    assert {:ok, workflow} = Exec.compile(flow, [])

    {workflow, observation} =
      workflow
      |> Workflow.put_run_context(%{_global: %{trace_id: "trace-child"}})
      |> Workflow.execute(%{value: 4})

    assert Exec.result(workflow, observation) ==
             {:ok, %{child: %{value: 5, trace_id: "trace-child"}}, [:child_effect]}
  end

  test "a rebuilt Subflow keeps its compiled child Workflow" do
    flow = parent_flow("compiled_subflow_rebuild")

    assert {:ok, workflow} = Exec.compile(flow, [])
    rebuilt = workflow |> Workflow.build_log() |> Workflow.from_log()

    {rebuilt, observation} =
      rebuilt
      |> Workflow.put_run_context(%{_global: %{trace_id: "rebuilt"}})
      |> Workflow.execute(%{value: 1})

    assert Exec.result(rebuilt, observation) ==
             {:ok, %{child: %{value: 2, trace_id: "rebuilt"}}, [:child_effect]}
  end

  defp parent_flow(name) do
    Flow.new!(%{
      name: name,
      components: [
        %{kind: :subflow, name: "child", flow: Child, params: %{value: Ref.input(:value)}}
      ],
      output: %{child: Ref.result("child")}
    })
  end
end
