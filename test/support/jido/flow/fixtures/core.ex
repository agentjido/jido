defmodule JidoActionTest.Fixtures.MathFlow do
  @moduledoc false

  use Jido.Flow,
    name: "math_flow",
    description: "Adds one and doubles the result"

  flow do
    step("add_one",
      action: JidoActionTest.Fixtures.Actions.Add,
      params: %{value: input(:value), amount: 1}
    )

    step("double",
      action: JidoActionTest.Fixtures.Actions.Multiply,
      params: %{value: select(result("add_one"), [:value]), amount: 2}
    )

    output(result("double"))
  end
end
