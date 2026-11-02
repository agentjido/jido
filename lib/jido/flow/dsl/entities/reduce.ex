defmodule Jido.Flow.DSL.Reduce do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    node?: true,
    name: :__reduce__,
    args: [:name, :__source__],
    identifier: :name,
    modules: [:action],
    describe:
      "Folds a list serially through one Action, in keyword or field-block form. An empty list returns the initial accumulator. See [Map And Reduce](flow-collections.html).",
    schema: [
      name: [type: :string, required: true, doc: "The unique component name. Pass it first."],
      collection: [
        type: :quoted,
        required: true,
        doc: "An expression that resolves to the list to fold."
      ],
      initial: [type: :quoted, required: true, doc: "The initial accumulator expression."],
      action: [
        type: :atom,
        required: true,
        doc: "The Action module to call for each item. Its result becomes the next accumulator."
      ],
      params: [
        type: :quoted,
        required: true,
        doc: "The call parameter expression. Use `item()` and `accumulator()` for local values."
      ]
    ]
end
