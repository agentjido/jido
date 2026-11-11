defmodule Jido.Exec.Compile.InvokeTest do
  use ExUnit.Case, async: true

  alias Jido.Exec
  alias Jido.Exec.Node.Invoke
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias Runic.Workflow

  defmodule Decide do
    use Jido.Action, name: "compiled_invoke_decide"
    def run(params, _context), do: {:ok, params, [:decision]}
  end

  defmodule Finish do
    use Jido.Action, name: "compiled_invoke_finish"
    def run(%{value: value}, _context), do: {:ok, %{value: value + 1}, [:finish]}
  end

  defmodule ContinueAction do
    use Jido.Action, name: "compiled_invoke_continue_action"
    def run(params, _context), do: {:continue, params, Finish}
  end

  defmodule Child do
    use Jido.Flow, name: "compiled_invoke_child"

    flow do
      step "finish", action: Finish, params: %{value: input(:value)}
      output result("finish")
    end
  end

  defmodule ContinueFlow do
    use Jido.Action, name: "compiled_invoke_continue_flow"
    def run(params, _context), do: {:continue, params, Child}
  end

  test "compile lowers one Invoke to one dedicated Runic Invoke component" do
    assert {:ok, %Workflow{} = workflow} =
             Exec.compile(invoke_flow("compiled_invoke_shape", ContinueAction), [])

    assert %Invoke{name: "next", definition: %{kind: :invoke}, terminal?: true} =
             invoke = Workflow.get_component(workflow, "next")

    assert [bindings: input_opts] = Runic.Component.inputs(invoke)
    assert input_opts[:type] == :any
    assert Keyword.keys(Runic.Component.outputs(invoke)) == [:value, :effects, :control]
  end

  test "Invoke can continue to an Action and preserves effect order" do
    assert Exec.run(invoke_flow("compiled_invoke_action", ContinueAction), %{value: 4}) ==
             {:ok, %{value: 5}, [:decision, :finish]}
  end

  test "Invoke can compile and run a dynamic Flow target" do
    assert Exec.run(invoke_flow("compiled_invoke_flow", ContinueFlow), %{value: 7}) ==
             {:ok, %{value: 8}, [:decision, :finish]}
  end

  test "a rebuilt Invoke can compile its dynamic Flow target" do
    assert {:ok, workflow} = Exec.compile(invoke_flow("compiled_invoke_rebuild", ContinueFlow), [])
    rebuilt = workflow |> Workflow.build_log() |> Workflow.from_log()
    {rebuilt, observation} = Workflow.execute(rebuilt, %{value: 2})

    assert Exec.result(rebuilt, observation) == {:ok, %{value: 3}, [:decision, :finish]}
  end

  defp invoke_flow(name, expander) do
    Flow.new!(%{
      name: name,
      components: [
        %{
          kind: :invoke,
          name: "next",
          decision: Decide,
          expander: expander,
          params: %{value: Ref.input(:value)}
        }
      ],
      output: Ref.result("next")
    })
  end
end
