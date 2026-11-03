defmodule Jido.Expr.Operation do
  @moduledoc "One inert operation in a `Jido.Expr` data tree."

  @enforce_keys [:operator, :operands]
  defstruct [:operator, :operands]

  @type t :: %__MODULE__{operator: atom(), operands: [term()]}
end
