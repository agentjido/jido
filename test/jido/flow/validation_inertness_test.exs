defmodule Jido.Flow.ValidationInertnessTest do
  use Covenant.Case, component: "jido_action.flow", async: true

  alias Jido.Flow
  alias Jido.Flow.Ref

  defmodule MustNotRun do
    use Jido.Action, name: "flow_validation_must_not_run"

    @impl true
    def run(_params, _context), do: raise("validation and compilation must not run Action work")
  end

  @tag obligation: "jido_action.flow.I9"
  test "validation, inspection, and compilation do not run Action work" do
    flow =
      Flow.new!(%{
        name: "inert_validation",
        components: [%{kind: :step, name: "probe", action: MustNotRun}],
        output: Ref.result("probe")
      })

    assert {:ok, ^flow} = Flow.validate(flow)

    assert {:ok, %{"probe" => %{references: [], needs: [], effective: []}}} =
             Flow.dependencies(flow)

    assert {:ok, %{name: "inert_validation"}} = Flow.explain(flow)
    assert {:ok, %Runic.Workflow{}} = Jido.Exec.compile(flow, [])
  end
end
