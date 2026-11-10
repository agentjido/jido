defmodule Jido.Flow.DSL.ParallelAction do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    name: :__parallel_action__,
    args: [:name, :__source__],
    identifier: :name,
    modules: [:action],
    describe: "Declares one named Action call in a Parallel component.",
    schema: [
      name: [
        type: :string,
        required: true,
        doc: "The unique Action name within this Parallel component."
      ],
      action: [
        type: :atom,
        required: true,
        doc: "The Action module to run."
      ],
      params: [
        type: :quoted,
        required: true,
        doc: "An expression that supplies the Action parameters."
      ]
    ]
end

defmodule Jido.Flow.DSL.Parallel do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    imports: [Jido.Flow.DSL.ParallelMacros],
    node?: true,
    name: :__parallel__,
    args: [:name, :__source__],
    identifier: :name,
    describe: "Runs different named Actions in parallel and joins their ordered results.",
    schema: [
      name: [
        type: :string,
        required: true,
        doc: "The unique component name. Pass it first."
      ],
      on_error: [
        type: {:one_of, [:fail_fast, :collect_errors]},
        default: :fail_fast,
        doc: "Stop on a step error, or return each error as ordered data."
      ]
    ],
    entities: [actions: [Jido.Flow.DSL.ParallelAction.entity()]]
end
