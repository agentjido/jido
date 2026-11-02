defmodule Jido.Plugin.DirectiveContext do
  alias Jido.Joi

  @moduledoc """
  Narrow post-commit context for one Plugin Directive.

  `turn_context` contains the admitted caller context for this Turn.
  It excludes the reserved Agent state and Signal fields. It is transient and
  is not added to the Directive, Agent checkpoint, or emitted Signals.
  """

  @schema Joi.struct(
            __MODULE__,
            %{
              turn_id: Joi.string(description: "Source Turn identifier"),
              agent_id: Joi.string(description: "Owning Agent identifier"),
              source_signal: Joi.struct(Jido.Signal, description: "Signal received by the Server"),
              effective_signal: Joi.struct(Jido.Signal, description: "Signal after live admission"),
              state_version: Joi.integer(description: "Committed Agent state version") |> Joi.min(0),
              plugin_state: Joi.any(description: "Committed value from the Plugin-owned Agent field"),
              turn_context: Joi.map(description: "Admitted transient Turn context") |> Joi.default(%{}),
              jido: Joi.atom(description: "Optional Jido instance") |> Joi.optional(),
              partition: Joi.any(description: "Optional Agent partition") |> Joi.optional()
            },
            coerce: true,
            unrecognized_keys: :error
          )

  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.Struct.enforce_keys(@schema)
  defstruct Joi.Struct.struct_fields(@schema)

  @doc "Returns the data schema for the Plugin Directive context."
  @spec schema() :: Joi.schema()
  def schema, do: @schema
end
