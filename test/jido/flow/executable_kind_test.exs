defmodule Jido.Flow.ExecutableKindTest do
  use ExUnit.Case, async: true

  alias Jido.Error.ValidationError
  alias Jido.Flow.Ref
  alias Jido.Test.Flow.Fixtures.NestedFlow

  test "embedded Action slots reject a Flow module" do
    components = [
      Jido.Test.Flow.Component.choice!(
        name: "choice",
        options: [
          Jido.Test.Flow.Component.option!(
            name: "nested",
            condition: Jido.Expr.new!(:==, [1, 1]),
            action: NestedFlow
          )
        ],
        fallback: Jido.Test.Flow.Component.fallback!(action: Jido.Test.Action.Fixtures.Actions.Add)
      ),
      Jido.Test.Flow.Component.map!(name: "map", collection: [], action: NestedFlow),
      Jido.Test.Flow.Component.reduce!(
        name: "reduce",
        collection: [],
        initial: %{},
        action: NestedFlow
      ),
      Jido.Test.Flow.Component.iterate!(
        name: "iterate",
        action: NestedFlow,
        state: Jido.Test.Flow.Component.state!(schema: Jido.Joi.map(), initial: %{}, update: %{}),
        completion: Jido.Expr.new!(:==, [Ref.iteration_index(), 0]),
        max_iterations: 1
      )
    ]

    Enum.each(components, fn component ->
      flow =
        Jido.Test.Flow.Builder.new!(
          name: "bad_#{component.name}",
          components: [component],
          output: Ref.result(component.name)
        )

      assert {:error, %ValidationError{details: details}} =
               Jido.Exec.compile(flow, [])

      assert details.component == component.name
      assert details.actual == :flow
      assert details.expected == :action
    end)
  end
end
