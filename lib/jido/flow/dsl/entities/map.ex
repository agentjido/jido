defmodule Jido.Flow.DSL.MapNode do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    node?: true,
    name: :__map__,
    args: [:name, :__source__],
    identifier: :name,
    modules: [:action],
    describe:
      "Runs one Action for each collection item, preserving input order. Use keyword or field-block form. See [Map And Reduce](flow-collections.html).",
    schema: [
      name: [
        type: :string,
        required: true,
        doc: "The unique component name. Pass it as the first positional argument."
      ],
      collection: [
        type: :quoted,
        required: true,
        doc: "An expression that resolves to the list of items to process."
      ],
      action: [
        type: :atom,
        required: true,
        doc: "The Action module to call for each item. Inline bodies are not supported."
      ],
      params: [
        type: :quoted,
        required: true,
        doc: "The parameter expression for each call. Use `item()` to read the current item."
      ],
      on_error: [
        type: {:one_of, [:fail_fast, :collect_errors]},
        default: :fail_fast,
        doc: "Stop on an item error, or return a success or error record for each item in input order."
      ]
    ]
end
