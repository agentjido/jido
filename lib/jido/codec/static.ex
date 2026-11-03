defmodule Jido.Codec.Static do
  @moduledoc false

  @doc false
  @spec validate(term()) :: :ok | {:error, String.t()}
  defdelegate validate(term), to: Jido.Joi.Static
end
