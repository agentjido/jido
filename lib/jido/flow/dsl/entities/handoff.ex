defmodule Jido.Flow.DSL.Handoff do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    node?: true,
    name: :__handoff__,
    args: [:name, :__source__],
    identifier: :name,
    modules: [:selector],
    describe: """
    Declares a root-terminal Turn handoff. The selector Action must return
    `{:handoff, input, target}`. The target is validated as a successor
    Instruction but is not run in the current Flow.
    """,
    schema: [
      name: [type: :string, required: true, doc: "The unique component name. Pass it first."],
      selector: [
        type: :atom,
        required: true,
        doc: "The Action module that selects the successor Action or Flow."
      ],
      params: [
        type: :quoted,
        required: true,
        doc: "An expression that supplies the selector Action parameters."
      ]
    ]
end
