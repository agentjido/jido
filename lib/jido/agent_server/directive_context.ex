defmodule Jido.AgentServer.DirectiveContext do
  @moduledoc """
  The narrow runtime context for post-commit Directive handling.

  It contains only the source Agent id, the turn Signals, and the transient
  context prepared for that Turn.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              turn_id:
                Zoi.string(description: "Optional source Turn identifier") |> Zoi.optional(),
              agent_id: Zoi.string(description: "Source Agent identifier"),
              source_signal: Zoi.any(description: "Signal received by the Server"),
              signal: Zoi.any(description: "Signal after Plugin preparation"),
              turn_context:
                Zoi.map(description: "Prepared transient Turn context") |> Zoi.default(%{})
            }
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for the Directive context."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema
end
