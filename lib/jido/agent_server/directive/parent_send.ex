defmodule Jido.AgentServer.Directive.ParentSend do
  alias Jido.Joi

  @moduledoc """
  Sends one Signal to the current parent Agent after commit.
  """

  @schema Joi.struct(
            __MODULE__,
            %{signal: Joi.any(description: "Signal to send to the parent")},
            coerce: true
          )

  @typedoc "A request to send one Signal to the current parent Agent."
  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.Struct.enforce_keys(@schema)
  defstruct Joi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end
