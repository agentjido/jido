defmodule JidoTest.Authoring.Agents.Fixtures.BoundedValue do
  use Jido.Agent,
    name: "authoring_bounded_value",
    schema: Zoi.object(%{value: Zoi.integer() |> Zoi.min(0) |> Zoi.max(10) |> Zoi.default(0)}),
    routes: [{"value.set", JidoTest.Authoring.Agents.Fixtures.SetValue}]
end
