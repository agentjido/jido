defmodule Jido.Plugin.Input do
  @moduledoc """
  Package-owned input for one Agent Turn.

  The pure Agent Plugin facet owns `prepared`. The live Agent Server Plugin
  facet owns `runtime`. Jido keeps the two values separate so that live
  admission cannot replace pure preparation.

  `prepared` must be portable. `runtime` is transient and can contain runtime
  terms. Neither value enters Agent state, checkpoints, or Signals unless
  application code copies portable data into an owned result.
  """

  defstruct prepared: nil, runtime: nil

  @type t :: %__MODULE__{prepared: term(), runtime: term()}

  @doc false
  @spec put_prepared(t(), term()) :: t()
  def put_prepared(%__MODULE__{} = input, value), do: %{input | prepared: value}

  @doc false
  @spec put_runtime(t(), term()) :: t()
  def put_runtime(%__MODULE__{} = input, value), do: %{input | runtime: value}
end
