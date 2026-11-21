Code.ensure_compiled!(Jido.Test.Action.Fixtures.Actions.Add)
Code.ensure_compiled!(Jido.Test.Action.Fixtures.Actions.Multiply)

defmodule Jido.Test.Flow.Fixtures.MathFlow do
  @moduledoc false
  use Jido.Flow,
    name: "math_flow",
    description: "Adds one and doubles the result"

  flow do
    step("add_one",
      action: Jido.Test.Action.Fixtures.Actions.Add,
      params: %{value: input(:value), amount: 1}
    )

    step("double",
      action: Jido.Test.Action.Fixtures.Actions.Multiply,
      params: %{value: select(result("add_one"), [:value]), amount: 2}
    )

    output(result("double"))
  end
end

defmodule Jido.Test.Flow.Fixtures.NestedFlow do
  @moduledoc false
  use Jido.Flow, name: "nested_fixture_flow"

  flow do
    step("add",
      action: Jido.Test.Action.Fixtures.Actions.Add,
      params: %{value: input(:value), amount: 1}
    )

    output(result("add"))
  end
end
