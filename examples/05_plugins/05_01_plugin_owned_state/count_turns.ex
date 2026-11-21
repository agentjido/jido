defmodule Jido.Examples.PluginStateAgent.CountTurns do
  @moduledoc "Owns one validated count of committed Turns."
  use Jido.Plugin

  @impl true
  def state_spec(_opts),
    do: {:turns, Jido.Joi.integer() |> Jido.Joi.min(0) |> Jido.Joi.max(1) |> Jido.Joi.default(0)}

  @impl true
  def reduce(reduction, _opts), do: {:ok, reduction.plugin_state + 1}
end
