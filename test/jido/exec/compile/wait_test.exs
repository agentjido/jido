defmodule Jido.Exec.Compile.WaitTest do
  use ExUnit.Case, async: true

  alias Jido.Exec
  alias Jido.Exec.Node.Wait
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias Runic.Workflow

  test "compile lowers one authored await to one Runic Wait component" do
    assert {:ok, %Workflow{} = workflow} = Exec.compile(wait_flow("compiled_wait_shape"), [])

    assert %Wait{name: "approval", options: [%{event: "approved"}]} =
             wait = Workflow.get_component(workflow, "approval")

    assert [bindings: input_opts] = Runic.Component.inputs(wait)
    assert input_opts[:type] == :any
    assert Keyword.keys(Runic.Component.outputs(wait)) == [:value, :effects, :control]
  end

  test "a compiled Wait opens and resumes through the host contract" do
    assert {:ok, workflow} = Exec.compile(wait_flow("compiled_wait_execution"), [])

    workflow =
      workflow
      |> Workflow.put_run_context(%{
        _global: Jido.Exec.Runtime.wait_context(%{}, "compiled-wait", 100)
      })
      |> Workflow.react_until_satisfied(%{id: 7})

    assert [request] = Jido.Exec.Runtime.pending_waits(workflow)

    candidate = %{
      input: %{id: "signal-1", event: "approved", payload: %{id: 7}},
      accepted_at: 101,
      order: 0
    }

    assert {:ok, workflow} = Jido.Exec.Runtime.resolve_wait(workflow, request.id, [candidate], 101)

    assert {:ok, %{id: 7}} =
             workflow
             |> Workflow.react_until_satisfied()
             |> Jido.Exec.Result.project()
  end

  test "a rebuilt Wait keeps its host-facing request" do
    assert {:ok, workflow} = Exec.compile(wait_flow("compiled_wait_rebuild"), [])
    rebuilt = workflow |> Workflow.build_log() |> Workflow.from_log()

    rebuilt =
      rebuilt
      |> Workflow.put_run_context(%{
        _global: Jido.Exec.Runtime.wait_context(%{}, "compiled-wait-rebuild", 10)
      })
      |> Workflow.react_until_satisfied(%{id: 2})

    assert [%{options: [%{event: "approved", match: %{id: 2}}]}] =
             Jido.Exec.Runtime.pending_waits(rebuilt)
  end

  defp wait_flow(name) do
    Flow.new!(%{
      name: name,
      components: [
        %{kind: :await, name: "approval", event: "approved", match: %{id: Ref.input(:id)}}
      ],
      output: Ref.result("approval")
    })
  end
end
