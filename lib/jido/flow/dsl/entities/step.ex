defmodule Jido.Flow.DSL.Step do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    node?: true,
    name: :__step__,
    args: [:name, :__source__],
    identifier: :name,
    modules: [:action],
    describe: """
    Declares one Action call, or a Subflow when the target is a Flow module.
    These fields describe module-backed Steps, in keyword or field-block form.
    Direct inline bodies use bindings instead of `action` and `params`; put
    Action settings in `inline:` and keep `needs` and `meta` at Step level.
    See [Steps And Output](flow-steps.html) and [Inline Actions](inline-actions.html).
    """,
    schema: [
      name: [type: :string, required: true, doc: "The unique Step name. Pass it first."],
      action: [type: :atom, required: true, doc: "The Action or Flow module to call."],
      params: [
        type: :quoted,
        required: true,
        doc: "An expression that supplies the target parameters."
      ]
    ]
end
