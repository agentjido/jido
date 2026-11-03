defmodule Jido.AgentServer.Directive.AgentStop do
  use Jido.Agent.Directive, built_in: true
  alias Jido.Joi
  @moduledoc "Stops and untracks one Agent activation."

  @schema Joi.struct(
            __MODULE__,
            %{
              name: Joi.any(description: "Agent name"),
              reason: Joi.any(description: "Stop reason") |> Joi.default(:normal)
            },
            coerce: true
          )

  @typedoc "A request to stop and untrack one child Agent."
  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.Struct.enforce_keys(@schema)
  defstruct Joi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end
