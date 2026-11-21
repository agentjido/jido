defmodule Jido.Flow.DSL.ChoiceOption do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    name: :__option__,
    args: [:name, :__source__],
    identifier: :name,
    modules: [:action],
    describe: "Declares one named Choice option, in keyword or field-block form. Only the first matching option runs.",
    schema: [
      name: [
        type: :string,
        required: true,
        doc: "The unique option name within this Choice. Pass it first."
      ],
      action: [
        type: :atom,
        required: true,
        doc: "The Action module to call when this option matches."
      ],
      params: [
        type: :quoted,
        required: true,
        doc: "An expression that supplies the selected Action parameters."
      ],
      condition: [
        type: :quoted,
        required: true,
        doc: "A Boolean Flow expression, tested in option declaration order."
      ]
    ]
end

defmodule Jido.Flow.DSL.Otherwise do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    name: :__otherwise__,
    args: [:__source__],
    modules: [:action],
    describe:
      "Declares the required unnamed fallback, in keyword or field-block form. It runs when no option matches, not when a selected Action fails.",
    schema: [
      action: [
        type: :atom,
        required: true,
        doc: "The Action module to call when no option matches."
      ],
      params: [
        type: :quoted,
        required: true,
        doc: "An expression that supplies the fallback parameters."
      ]
    ]
end

defmodule Jido.Flow.DSL.Choice do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    imports: [Jido.Flow.DSL.ChoiceMacros],
    node?: true,
    name: :__choice__,
    args: [:name, :__source__],
    identifier: :name,
    describe: """
    Declares ordered options and exactly one `otherwise` fallback in a block.
    Result references in all targets create dependencies, even in unselected
    options. See [Choices And Conditions](flow-choices.html).
    """,
    schema: [
      name: [type: :string, required: true, doc: "The unique component name. Pass it first."]
    ],
    entities: [
      options: [Jido.Flow.DSL.ChoiceOption.entity()],
      fallback: [Jido.Flow.DSL.Otherwise.entity()]
    ],
    singleton_entity_keys: [:fallback]
end
