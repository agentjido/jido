defmodule Jido.AgentServer.Directive.ProcessStart do
  @moduledoc "Starts one untracked process under the Jido instance supervisor."

  @schema Zoi.struct(
            __MODULE__,
            %{child_spec: Zoi.any(description: "OTP child specification")},
            coerce: true
          )

  @typedoc "A request to start one independent OTP child under the Jido instance."
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end
