defmodule Jido.Plugin.Scheduler.Schedule do
  @moduledoc "Sends one delayed Signal to the Agent."

  @schema Zoi.struct(
            __MODULE__,
            %{
              delay_ms: Zoi.integer(description: "Delay in milliseconds") |> Zoi.min(0),
              signal: Zoi.struct(Jido.Signal, description: "Signal to send")
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end
