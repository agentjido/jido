defmodule Jido.Examples.Plugins.PersistedState.Package do
  @moduledoc "Owns one state value and converts it for persistence."
  use Jido.Plugin

  @impl true
  def state_spec(_opts), do: {:owned, Zoi.integer() |> Zoi.default(0)}

  @owned_prefix "owned:"

  @impl true
  def dump(value, _context, _opts) when is_integer(value),
    do: {:ok, @owned_prefix <> Integer.to_string(value)}

  @impl true
  def load(@owned_prefix <> encoded, _context, _opts) do
    case Integer.parse(encoded) do
      {value, ""} -> {:ok, value}
      _invalid -> {:error, :invalid_owned_value}
    end
  end

  def load(_value, _context, _opts), do: {:error, :invalid_owned_value}
end
