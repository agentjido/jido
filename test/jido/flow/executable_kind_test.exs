defmodule Jido.Flow.ExecutableKindTest do
  use ExUnit.Case, async: true

  alias Jido.Error.ValidationError
  alias Jido.Flow.Ref
  alias JidoActionTest.Fixtures.NestedFlow

  test "embedded Action slots reject a Flow module" do
    components = [
      JidoActionTest.FlowComponent.choice!(
        name: "choice",
        options: [
          JidoActionTest.FlowComponent.option!(
            name: "nested",
            condition: Jido.Expr.new!(:==, [1, 1]),
            action: NestedFlow
          )
        ],
        fallback: JidoActionTest.FlowComponent.fallback!(action: JidoActionTest.Fixtures.Actions.Add)
      ),
      JidoActionTest.FlowComponent.map!(name: "map", collection: [], action: NestedFlow),
      JidoActionTest.FlowComponent.reduce!(
        name: "reduce",
        collection: [],
        initial: %{},
        action: NestedFlow
      ),
      JidoActionTest.FlowComponent.iterate!(
        name: "iterate",
        action: NestedFlow,
        state: JidoActionTest.FlowComponent.state!(schema: Jido.Joi.map(), initial: %{}, update: %{}),
        completion: Jido.Expr.new!(:==, [Ref.iteration_index(), 0]),
        max_iterations: 1
      )
    ]

    Enum.each(components, fn component ->
      flow =
        JidoActionTest.FlowBuilder.new!(
          name: "bad_#{component.name}",
          components: [component],
          output: Ref.result(component.name)
        )

      assert {:error, %ValidationError{details: details}} =
               Jido.Exec.Compiler.validate(flow)

      assert details.component == component.name
      assert details.actual == :flow
      assert details.expected == :action
    end)
  end
end
