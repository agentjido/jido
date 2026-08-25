defmodule Jido.Agent.Strategy.Command do
  @moduledoc false

  use Jido.Action,
    name: "jido_strategy_command",
    description: "Internal target for commands handled by an agent strategy",
    schema: []

  @impl true
  def run(_params, _context), do: {:error, :strategy_command_not_handled}
end
