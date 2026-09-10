defmodule Jido.Agent.Directive.SpawnProcess do
  @moduledoc "Starts one untracked process under the Jido instance supervisor."

  @schema Zoi.struct(
            __MODULE__,
            %{child_spec: Zoi.any(description: "OTP child specification")},
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end
