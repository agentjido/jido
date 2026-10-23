defmodule Jido.Agent.Directive.Reply do
  @moduledoc """
  Represents one correlated Signal response to the current request.

  A Reply does not dispatch its Signal and does not contain a delivery address.
  Agent routes can create a Reply from validated executable output. Callers that
  build this low-level Directive must supply a complete correlated Signal.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{signal: Zoi.any(description: "Correlated reply Signal")},
            coerce: true
          )

  @typedoc "One correlated response request for the current Agent Turn."
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end
