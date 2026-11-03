defmodule Jido.Agent.Directive.AgentSend do
  alias Jido.Joi
  @moduledoc "Sends one Signal to a tracked Agent activation after commit."

  @schema Joi.struct(
            __MODULE__,
            %{
              name: Joi.any(description: "Agent name"),
              signal: Joi.any(description: "Signal to send to the child")
            },
            coerce: true
          )

  @typedoc "A request to send one Signal to a tracked child Agent."
  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.Struct.enforce_keys(@schema)
  defstruct Joi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end
