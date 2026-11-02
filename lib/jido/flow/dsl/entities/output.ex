defmodule Jido.Flow.DSL.Output do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    name: :__output__,
    args: [:value, :__source__],
    describe:
      "Declares the required, non-nil Flow output. Pass the value as the only argument; there is no field-block form. Output must be the final declaration. See [Steps And Output](flow-steps.html).",
    schema: [
      value: [
        type: :quoted,
        required: true,
        doc: "The Flow result expression. Pass it directly to `output`, not as a keyword field."
      ]
    ]
end
