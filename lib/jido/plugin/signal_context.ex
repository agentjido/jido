defmodule Jido.Plugin.SignalContext do
  alias Jido.Joi

  @moduledoc """
  Narrow context for one outbound Plugin Signal transformation.

  `turn_context` contains caller and Plugin additions. It does not contain the
  reserved Action context fields for the complete Agent state or effective
  Signal.
  """

  @schema Joi.struct(
            __MODULE__,
            %{
              turn_id: Joi.string(description: "Source Turn identifier"),
              agent_id: Joi.string(description: "Owning Agent identifier"),
              source_signal: Joi.struct(Jido.Signal, description: "Unchanged Signal received by the Server"),
              effective_signal: Joi.struct(Jido.Signal, description: "Signal used for the Agent Turn"),
              turn_context: Joi.map(description: "Prepared transient Turn context") |> Joi.default(%{}),
              target: Joi.any(description: "Outbound Signal target"),
              state_version: Joi.integer(description: "Committed Agent state version") |> Joi.min(0),
              plugin_state: Joi.any(description: "Committed value from the Plugin-owned Agent field"),
              jido: Joi.atom(description: "Optional Jido instance") |> Joi.optional(),
              partition: Joi.any(description: "Optional Agent partition") |> Joi.optional()
            },
            coerce: true,
            unrecognized_keys: :error
          )

  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.Struct.enforce_keys(@schema)
  defstruct Joi.Struct.struct_fields(@schema)

  @doc "Returns the data schema for the outbound Signal context."
  @spec schema() :: Joi.schema()
  def schema, do: @schema
end
