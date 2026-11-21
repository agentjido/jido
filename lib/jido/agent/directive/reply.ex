defmodule Jido.Agent.Directive.Reply do
  alias Jido.Joi

  @moduledoc """
  Represents one correlated Signal response to the current request.

  A Reply does not dispatch its Signal and does not contain a delivery address.
  Agent routes can create a Reply from validated executable output. Callers that
  build this low-level Directive must supply a complete correlated Signal.
  """

  @schema Joi.struct(
            __MODULE__,
            %{signal: Joi.any(description: "Correlated reply Signal")},
            coerce: true
          )

  @typedoc "One correlated response request for the current Agent Turn."
  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.enforce_keys(@schema)
  defstruct Joi.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end
