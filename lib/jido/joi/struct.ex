defmodule Jido.Joi.Struct do
  @moduledoc """
  Defines public struct fields from a Joi schema.

  The generated struct stays compatible with the underlying Zoi schema.
  """

  @spec enforce_keys(Jido.Joi.schema()) :: [atom()]
  defdelegate enforce_keys(schema), to: Zoi.Struct

  @spec struct_fields(Jido.Joi.schema()) :: [atom() | {atom(), term()}]
  defdelegate struct_fields(schema), to: Zoi.Struct
end
