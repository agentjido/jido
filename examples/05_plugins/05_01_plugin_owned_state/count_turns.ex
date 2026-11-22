defmodule Jido.Examples.PluginStateAgent.CountTurns do
  @moduledoc "Owns one validated count of committed Turns."

  alias Jido.Joi

  use Jido.Plugin

  @impl true
  def state_spec(_opts),
    do: {:turns, Joi.integer() |> Joi.min(0) |> Joi.max(1) |> Joi.default(0)}

  @impl true
  def reduce(reduction, _opts), do: {:ok, reduction.plugin_state + 1}
end
