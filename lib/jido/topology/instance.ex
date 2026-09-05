defmodule Jido.Topology.Instance do
  @moduledoc "A topology definition with validated input and a local execution plan."

  @schema Zoi.struct(__MODULE__, %{
            id: Zoi.string(),
            definition: Zoi.any(),
            input: Zoi.map(),
            plan: Zoi.any()
          })
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the instance schema."
  def schema, do: @schema
end
