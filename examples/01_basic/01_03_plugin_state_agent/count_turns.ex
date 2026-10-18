defmodule Jido.Examples.PluginStateAgent.CountTurns do
  @moduledoc "Owns one validated count of committed Turns."
  use Jido.Plugin

  @impl true
  def state_spec(_opts),
    do: {:turns, Zoi.integer() |> Zoi.min(0) |> Zoi.max(1) |> Zoi.default(0)}

  @impl true
  def reduce(reduction, _opts), do: {:ok, reduction.plugin_state + 1}
end
