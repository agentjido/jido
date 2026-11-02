defmodule Jido.Flow.DSL.IterateState do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    name: :__state__,
    args: [:schema, :__source__],
    modules: [:schema],
    describe:
      "Declares the required Iterate state, in keyword or field-block form. The schema validates the initial value and every replacement. State is replaced, not merged.",
    schema: [
      schema: [
        type: :any,
        required: true,
        doc: "The static State schema. Pass it first."
      ],
      initial: [
        type: :quoted,
        required: true,
        doc: "An expression that supplies the initial State."
      ]
    ]
end

defmodule Jido.Flow.DSL.Iterate do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    imports: [Jido.Flow.DSL.IterateMacros],
    node?: true,
    name: :__iterate__,
    args: [:name, :__source__],
    identifier: :name,
    modules: [:action],
    describe: """
    Declares one required `state` and an Action body in a field block.
    Choose exactly one termination form: `repeat`, without `max_iterations`,
    or `while` with `max_iterations`. The condition is checked before each call;
    if it remains true at the bound, execution fails.
    See [Iterate And State](flow-iterate-state.html).
    """,
    schema: [
      name: [type: :string, required: true, doc: "The unique component name. Pass it first."],
      action: [
        type: :atom,
        required: true,
        doc: "The Action module for the loop body. Flow targets and inline bodies are not supported."
      ],
      params: [
        type: :quoted,
        required: true,
        doc: "The body parameter expression. Use `state()` and `iteration_index()` for local values."
      ],
      update: [
        type: :quoted,
        doc:
          "The replacement State expression after each successful call. If omitted, Jido uses the complete `body_result()` instead."
      ],
      while: [
        type: :quoted,
        doc: "A Boolean head condition. Requires `max_iterations`; cannot be combined with `repeat`."
      ],
      repeat: [
        type: :pos_integer,
        doc: "A fixed count from 1 through 10,000. Cannot be combined with `while` or `max_iterations`."
      ],
      max_iterations: [
        type: :pos_integer,
        doc: "The bound from 1 through 10,000 for a `while` loop. Required with `while` and forbidden with `repeat`."
      ]
    ],
    entities: [state: [Jido.Flow.DSL.IterateState.entity()]],
    singleton_entity_keys: [:state]
end
