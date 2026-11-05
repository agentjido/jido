defmodule Jido.Plugin.Scheduler.Schedule do
  alias Jido.Joi
  @moduledoc "Sends one delayed Signal to the Agent."

  @schema Joi.struct(
            __MODULE__,
            %{
              delay_ms: Joi.integer(description: "Delay in milliseconds") |> Joi.min(0),
              signal: Joi.struct(Jido.Signal, description: "Signal to send")
            },
            coerce: true
          )

  @typedoc "A delayed Signal Directive."
  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.enforce_keys(@schema)
  defstruct Joi.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc "Validates one delayed Signal request."
  @spec validate(t()) :: {:ok, t()} | {:error, term()}
  def validate(%__MODULE__{} = directive),
    do: Jido.Agent.Directive.parse(@schema, Map.from_struct(directive))
end
