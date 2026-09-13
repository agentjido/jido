defmodule JidoTest.Authoring.Agents.Fixtures.BuiltFlow do
  alias Jido.Flow.{Builder, Ref}

  {:ok, flow} =
    Builder.new(name: "corpus_built_flow", schema: Zoi.object(%{value: Zoi.integer()}))
    |> Builder.step("set", JidoTest.Authoring.Agents.Fixtures.SetTotal, %{
      value: Ref.input(:value)
    })
    |> Builder.output(Ref.result("set"))
    |> Builder.build()

  @flow flow
  use Jido.Agent, name: "authoring_built_flow"

  agent do
    schema Zoi.object(%{total: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/authoring/built_flow"

    route "total.set", @flow do
      define :set, args: [:value]
    end
  end
end
