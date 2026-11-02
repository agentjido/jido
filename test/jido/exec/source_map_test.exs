defmodule Jido.Exec.SourceMapTest do
  use Covenant.Case, component: "jido_action.boundary", async: true

  alias Jido.Exec
  alias Jido.Instruction

  defmodule FailAction do
    use Jido.Action, name: "exec_v2_source_failure"

    @impl true
    def run(_params, _context), do: {:error, Jido.Action.Error.execution_error("source failure")}
  end

  defmodule BadOutputAction do
    use Jido.Action, name: "exec_v2_bad_flow_output"

    @impl true
    def run(_params, _context), do: {:ok, %{value: "bad"}}
  end

  defmodule FailingFlow do
    use Jido.Flow, name: "exec_v2_source_map"

    flow do
      step "fail", action: FailAction, params: %{}
      output result("fail")
    end
  end

  defmodule InvalidOutputFlow do
    use Jido.Flow,
      name: "exec_v2_invalid_output",
      output_schema: Zoi.object(%{value: Zoi.integer()})

    flow do
      step "bad", action: BadOutputAction, params: %{}
      output result("bad")
    end
  end

  defmodule ThrowingFlow do
    @behaviour Jido.Flow

    @impl Jido.Flow
    def flow, do: throw(:flow_failed)

    @impl Jido.Flow
    def validate_params(params), do: {:ok, params}

    @impl Jido.Flow
    def validate_output(output), do: {:ok, output}
  end

  @tag obligation: "jido_action.boundary.I5"
  test "Exec automatically applies a Flow module source map" do
    expected = FailingFlow.__jido_flow_source_map__()[[:components, "fail"]]

    workflow = Exec.compile!(FailingFlow)
    node = Runic.Workflow.get_component(workflow, "fail")
    assert node.flow.location == expected

    fact = Runic.Workflow.Fact.new(value: Jido.Exec.Frame.new(%{}))
    assert {:ok, runnable} = Runic.Workflow.Invokable.prepare(node, workflow, fact)
    failed = Runic.Workflow.Invokable.execute(node, runnable)
    assert failed.status == :failed
    assert failed.error.details.node == "fail"
    assert failed.error.details.source == expected
    assert failed.error.details.node_path == ["fail"]

    assert {:error, error} = Exec.run(FailingFlow)
    assert error.details.source == expected
    assert error.details.node_path == ["fail"]
  end

  @tag obligation: "jido_action.boundary.I3"
  test "Flow output validation includes the DSL output location" do
    expected = InvalidOutputFlow.__jido_flow_source_map__()[[:output]]

    assert {:error, error} = Exec.run(InvalidOutputFlow)
    assert %Jido.Action.Error.InvalidInputError{} = error
    assert error.details.source == expected
    assert error.details.phase == :flow_output
  end

  @tag obligation: "jido_action.boundary.I5"
  test "Flow Instructions transmute to the compiled Runic Workflow" do
    instruction = Instruction.new!(target: FailingFlow)

    assert %Runic.Workflow{} = Runic.Transmutable.to_workflow(instruction)
  end

  @tag obligation: "jido_action.boundary.I2"
  test "compiler catches a non-local Flow definition failure" do
    assert {:error, error} = Exec.compile(ThrowingFlow)
    assert error.details.kind == :throw
    assert error.details.reason == :flow_failed
  end
end
