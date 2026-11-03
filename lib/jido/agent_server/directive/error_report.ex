defmodule Jido.AgentServer.Directive.ErrorReport do
  use Jido.Agent.Directive, built_in: true
  alias Jido.Joi
  @moduledoc "Reports a structured turn or runtime error to the Server policy."

  @schema Joi.struct(
            __MODULE__,
            %{
              error: Joi.any(description: "Error value"),
              context: Joi.atom(description: "Optional error context") |> Joi.optional()
            },
            coerce: true
          )

  @typedoc "A request to apply the AgentServer error policy after commit."
  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.Struct.enforce_keys(@schema)
  defstruct Joi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end
