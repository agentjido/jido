defmodule JidoTest.Authoring.Agents.Fixtures.BuiltFlow do
  alias Jido.Flow.Ref

  {:ok, flow} =
    Jido.Flow.new(
      name: "corpus_built_flow",
      schema: Zoi.object(%{value: Zoi.integer()}),
      components: [
        Jido.Flow.Step.new!(
          name: "set",
          action: JidoTest.Authoring.Agents.Fixtures.SetTotal,
          params: %{value: Ref.input(:value)}
        )
      ],
      output: Ref.result("set")
    )

  @flow flow
  use Jido.Agent, name: "authoring_built_flow"

  agent do
    schema Zoi.object(%{total: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/authoring/built_flow"

    route "total.set", @flow, as: :set
  end
end
