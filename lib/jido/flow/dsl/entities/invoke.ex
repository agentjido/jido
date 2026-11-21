defmodule Jido.Flow.DSL.Invoke do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    node?: true,
    name: :__invoke__,
    args: [:name, :__source__],
    identifier: :name,
    modules: [:decision, :expander],
    describe: """
    Declares a composable dynamic call. The decision Action returns data. The
    expander Action can return the Invoke result or select an Action or Flow
    target with `{:continue, input, target}`. Invoke can have downstream
    components and a Flow can contain more than one Invoke. See
    [Dynamic Flows](dynamic-flows.html).
    """,
    schema: [
      name: [type: :string, required: true, doc: "The unique component name. Pass it first."],
      decision: [
        type: :atom,
        required: true,
        doc: "The Action module that receives the Invoke parameters and returns decision data."
      ],
      expander: [
        type: :atom,
        required: true,
        doc: "The Action module that receives the decision data. It can return a result or select an Action or Flow."
      ],
      params: [
        type: :quoted,
        required: true,
        doc: "An expression that supplies the decision Action parameters."
      ]
    ]
end
