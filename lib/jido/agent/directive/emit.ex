defmodule Jido.Agent.Directive.Emit do
  alias Jido.Joi
  @moduledoc "Dispatches one Signal after the Agent state commit."

  @schema Joi.struct(
            __MODULE__,
            %{
              signal: Joi.any(description: "Signal to dispatch"),
              dispatch: Joi.any(description: "Optional Signal dispatch configuration") |> Joi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.Struct.enforce_keys(@schema)
  defstruct Joi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end
