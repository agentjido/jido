defmodule Jido.AgentServer.Directive.ServerStop do
  alias Jido.Joi
  @moduledoc "Stops the Agent Server after the Agent state commit."

  @schema Joi.struct(
            __MODULE__,
            %{reason: Joi.any(description: "Stop reason") |> Joi.default(:normal)},
            coerce: true
          )

  @typedoc "A terminal request to stop the AgentServer after commit."
  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.Struct.enforce_keys(@schema)
  defstruct Joi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end
