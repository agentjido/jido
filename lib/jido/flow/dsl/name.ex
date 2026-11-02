defmodule Jido.Flow.DSL.Name do
  @moduledoc false

  alias Jido.Authoring.Config

  @doc false
  @spec normalize(term()) :: {:ok, String.t()} | {:error, String.t()}
  def normalize(value) when is_atom(value) and value not in [nil, true, false],
    do: normalize(Atom.to_string(value))

  def normalize(value) when is_binary(value) do
    case Config.validate_name(value, subject: "Flow Step") do
      :ok -> {:ok, value}
      {:error, message} -> {:error, message}
    end
  end

  def normalize(_value), do: {:error, "Flow Step name must be a string or atom"}
end
