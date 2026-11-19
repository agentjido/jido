defmodule Jido.Exec.Compile.InvokeTest do
  use ExUnit.Case, async: true

  alias Jido.Exec
  alias Jido.Exec.Node.Invoke
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias Jido.Instruction
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

  defmodule RawInput do
    use Jido.Action, name: "compiled_invoke_raw"

    @impl true
    def on_before_validate_params(input) when is_map(input), do: {:ok, input}
    def on_before_validate_params(input), do: {:ok, %{value: input}}

    @impl true
    def run(input, _context), do: {:ok, input}
  end

  defmodule ContinueBound do
    use Jido.Action, name: "compiled_invoke_bound"

    def run(params, _context) do
      {:ok, instruction} = Instruction.bind(Instruction.template(:action, RawInput), "bound", %{})
      {:continue, if(params.value == :bound, do: %{}, else: params), instruction}
    end
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
    flow = invoke_flow("compiled_invoke_flow", ContinueFlow)
    assert {:ok, %{requirements: [], advisories: []}} = Flow.explain(flow)
    assert Exec.run(flow, %{value: 7}) == {:ok, %{value: 8}, [:decision, :finish]}
  end

  test "Exec delivers raw bound inputs to the target hook" do
    template = Instruction.template(:action, RawInput)

    for raw <- ["bound", nil, ["raw", "list"]] do
      assert {:ok, bound} = Instruction.bind(template, raw, %{})
      assert Exec.run(bound) == {:ok, %{value: raw}}
      assert Exec.run(bound, %{value: "replacement"}) == {:ok, %{value: "replacement"}}
    end

    {:ok, keyword} = Instruction.bind(template, [keep: true, value: :keyword], %{})
    assert Exec.run(keyword, %{value: "override"}) == {:ok, %{keep: true, value: "override"}}
  end

  test "Invoke uses a raw bound input or replaces it with explicit parameters" do
    flow = invoke_flow("compiled_invoke_bound_input", ContinueBound)
    assert Exec.run(flow, %{value: :bound}) == {:ok, %{value: "bound"}, [:decision]}
    assert Exec.run(flow, %{value: "replacement"}) == {:ok, %{value: "replacement"}, [:decision]}
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
