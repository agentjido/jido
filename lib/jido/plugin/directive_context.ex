defmodule Jido.Plugin.DirectiveContext do
  @moduledoc """
  Narrow post-commit context for one Plugin Directive.

  `turn_context` contains prepared caller and Plugin additions for this Turn.
  It excludes the reserved Agent state and Signal fields. It is transient and
  is not added to the Directive, Agent checkpoint, or emitted Signals.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              turn_id: Zoi.string(description: "Source Turn identifier"),
              agent_id: Zoi.string(description: "Owning Agent identifier"),
              source_signal:
                Zoi.struct(Jido.Signal, description: "Signal received by the Server"),
              effective_signal:
                Zoi.struct(Jido.Signal, description: "Signal after Plugin preparation"),
              state_version:
                Zoi.integer(description: "Committed Agent state version") |> Zoi.min(0),
              plugin_state: Zoi.any(description: "Committed Plugin-owned Agent state"),
              turn_context:
                Zoi.map(description: "Prepared transient Turn context") |> Zoi.default(%{}),
              jido: Zoi.atom(description: "Optional Jido instance") |> Zoi.optional(),
              partition: Zoi.any(description: "Optional Agent partition") |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for the Plugin Directive context."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema
end
