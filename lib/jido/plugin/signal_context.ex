defmodule Jido.Plugin.SignalContext do
  @moduledoc """
  Narrow context for one outbound Plugin Signal transformation.

  `turn_context` contains caller and Plugin additions. It does not contain the
  reserved Action context fields for the complete Agent state or effective
  Signal.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              turn_id: Zoi.string(description: "Source Turn identifier"),
              agent_id: Zoi.string(description: "Owning Agent identifier"),
              source_signal:
                Zoi.struct(Jido.Signal, description: "Unchanged Signal received by the Server"),
              effective_signal:
                Zoi.struct(Jido.Signal, description: "Signal used for the Agent Turn"),
              turn_context:
                Zoi.map(description: "Prepared transient Turn context") |> Zoi.default(%{}),
              target: Zoi.any(description: "Outbound Signal target"),
              state_version:
                Zoi.integer(description: "Committed Agent state version") |> Zoi.min(0),
              plugin_state: Zoi.any(description: "Committed Plugin-owned Agent state"),
              jido: Zoi.atom(description: "Optional Jido instance") |> Zoi.optional(),
              partition: Zoi.any(description: "Optional Agent partition") |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for the outbound Signal context."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema
end
