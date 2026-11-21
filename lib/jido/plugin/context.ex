defmodule Jido.Plugin.Context do
  alias Jido.Joi

  @moduledoc """
  Phase-tagged context for one Plugin runtime callback.

  `:signal` contexts prepare one outbound Signal and include its `target`.
  `:directive` contexts dispatch one post-commit Directive. Both phases keep
  the admitted caller context transient and separate from Agent state.
  """

  @common_fields %{
    turn_id: Joi.string(description: "Source Turn identifier"),
    agent_id: Joi.string(description: "Owning Agent identifier"),
    source_signal: Joi.struct(Jido.Signal, description: "Signal received by the Server"),
    effective_signal: Joi.struct(Jido.Signal, description: "Signal used for the Agent Turn"),
    state_version: Joi.integer(description: "Committed Agent state version") |> Joi.min(0),
    plugin_state: Joi.any(description: "Committed value from the Plugin-owned Agent field"),
    turn_context: Joi.map(description: "Admitted transient Turn context") |> Joi.default(%{}),
    jido: Joi.atom(description: "Optional Jido instance") |> Joi.optional(),
    partition: Joi.any(description: "Optional Agent partition") |> Joi.optional()
  }

  @signal_schema Joi.struct(
                   __MODULE__,
                   Map.merge(@common_fields, %{
                     phase: Joi.literal(:signal),
                     target: Joi.any(description: "Outbound Signal target")
                   }),
                   coerce: true,
                   unrecognized_keys: :error
                 )

  @directive_schema Joi.struct(
                      __MODULE__,
                      Map.put(@common_fields, :phase, Joi.literal(:directive)),
                      coerce: true,
                      unrecognized_keys: :error
                    )

  @type phase :: :signal | :directive
  @type t :: %__MODULE__{
          phase: phase(),
          turn_id: String.t(),
          agent_id: String.t(),
          source_signal: Jido.Signal.t(),
          effective_signal: Jido.Signal.t(),
          state_version: non_neg_integer(),
          plugin_state: term(),
          turn_context: map(),
          target: term() | nil,
          jido: atom() | nil,
          partition: term() | nil
        }
  @type signal_t :: %__MODULE__{phase: :signal, target: term()}
  @type directive_t :: %__MODULE__{phase: :directive, target: nil}

  @enforce_keys [
    :phase,
    :turn_id,
    :agent_id,
    :source_signal,
    :effective_signal,
    :state_version,
    :plugin_state
  ]
  defstruct @enforce_keys ++ [turn_context: %{}, target: nil, jido: nil, partition: nil]

  @doc "Returns the schema for one Plugin callback phase."
  @spec schema(phase()) :: Joi.schema()
  def schema(:signal), do: @signal_schema
  def schema(:directive), do: @directive_schema
end
