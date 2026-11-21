defmodule Jido.Exec.Compile.HandoffTest do
  use ExUnit.Case, async: true

  alias Jido.Error
  alias Jido.Exec
  alias Jido.Exec.Node.Handoff
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias Jido.Instruction
  alias Runic.Workflow

  defmodule Target do
    use Jido.Action, name: "compiled_handoff_target"
    def run(params, _context), do: {:ok, params}
  end

  defmodule Select do
    use Jido.Action, name: "compiled_handoff_select"
    def run(params, _context), do: {:handoff, params, Target}
  end

  defmodule Invalid do
    use Jido.Action, name: "compiled_handoff_invalid"
    def run(params, _context), do: {:ok, params}
  end

  test "compile lowers one Handoff to one dedicated Runic Handoff component" do
    assert {:ok, %Workflow{} = workflow} = Exec.compile(handoff_flow("compiled_handoff_shape", Select), [])

    assert %Handoff{name: "next", definition: %{kind: :handoff}} =
             handoff = Workflow.get_component(workflow, "next")

    assert [bindings: input_opts] = Runic.Component.inputs(handoff)
    assert input_opts[:type] == :any
    assert Keyword.keys(Runic.Component.outputs(handoff)) == [:value, :effects, :control]
  end

  test "Handoff returns a validated successor instruction" do
    assert {:handoff, %Instruction{kind: :action, target: Target, params: %{value: 4}}, []} =
             Exec.run(handoff_flow("compiled_handoff_execution", Select), %{value: 4})
  end

  test "Handoff rejects ordinary selector output" do
    assert {:error, %Error.ExecutionError{} = error} =
             Exec.run(handoff_flow("compiled_handoff_invalid", Invalid), %{value: 4})

    assert error.message == "Handoff selector must return a handoff control result"
    assert error.details.reason == :invalid_handoff_return
  end

  test "a rebuilt Handoff keeps its control result" do
    assert {:ok, workflow} = Exec.compile(handoff_flow("compiled_handoff_rebuild", Select), [])
    rebuilt = workflow |> Workflow.build_log() |> Workflow.from_log()
    {rebuilt, observation} = Workflow.execute(rebuilt, %{value: 9})

    assert Exec.result(rebuilt, observation) ==
             {:handoff, %Instruction{kind: :action, target: Target, params: %{value: 9}}, []}
  end

  defp handoff_flow(name, selector) do
    Flow.new!(%{
      name: name,
      components: [
        %{kind: :handoff, name: "next", selector: selector, params: %{value: Ref.input(:value)}}
      ],
      output: Ref.result("next")
    })
  end
end
