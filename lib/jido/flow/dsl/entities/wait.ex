defmodule Jido.Flow.DSL.Timer do
  @moduledoc false
  use Jido.Flow.DSL.Entity,
    node?: true,
    name: :__timer__,
    args: [:name, :__source__],
    identifier: :name,
    describe: "Waits for a host-supplied absolute deadline.",
    schema: [
      name: [type: :string, required: true, doc: "The stable component or option name."],
      after_ms: [
        type: :non_neg_integer,
        required: true,
        doc: "The delay from activation, in milliseconds."
      ]
    ]
end

defmodule Jido.Flow.DSL.Await do
  @moduledoc false
  use Jido.Flow.DSL.Entity,
    node?: true,
    name: :__await__,
    args: [:name, :__source__],
    identifier: :name,
    describe: "Waits for one matching host input.",
    schema: [
      name: [type: :string, required: true, doc: "The stable component or option name."],
      event: [type: :string, required: true, doc: "The host input event name."],
      match: [
        type: :quoted,
        default: {:%{}, [], []},
        doc: "Payload fields to match; values can use Flow references."
      ]
    ]
end

defmodule Jido.Flow.DSL.TimerOption do
  @moduledoc false
  use Jido.Flow.DSL.Entity,
    name: :__timer_option__,
    args: [:name, :__source__],
    identifier: :name,
    describe: "One timer in a Selection.",
    schema: [
      name: [type: :string, required: true, doc: "The stable component or option name."],
      after_ms: [
        type: :non_neg_integer,
        required: true,
        doc: "The delay from activation, in milliseconds."
      ]
    ]
end

defmodule Jido.Flow.DSL.AwaitOption do
  @moduledoc false
  use Jido.Flow.DSL.Entity,
    name: :__await_option__,
    args: [:name, :__source__],
    identifier: :name,
    describe: "One event in a Selection.",
    schema: [
      name: [type: :string, required: true, doc: "The stable component or option name."],
      event: [type: :string, required: true, doc: "The host input event name."],
      match: [
        type: :quoted,
        default: {:%{}, [], []},
        doc: "Payload fields to match; values can use Flow references."
      ]
    ]
end

defmodule Jido.Flow.DSL.Selection do
  @moduledoc false
  use Jido.Flow.DSL.Entity,
    node?: true,
    name: :__selection__,
    args: [:name, :__source__],
    imports: [Jido.Flow.DSL.SelectionMacros],
    identifier: :name,
    describe: "Selects one timer or matching event. Does not race Actions.",
    schema: [name: [type: :string, required: true, doc: "The stable component or option name."]],
    entities: [options: [Jido.Flow.DSL.TimerOption.entity(), Jido.Flow.DSL.AwaitOption.entity()]]
end
