defmodule Jido.Examples.Research.ChildTopologyRuntime.Observe do
  @moduledoc "Stores lifecycle Signals for both topology directors."
  use Jido.Action, name: "child_runtime_observe", schema: Zoi.map()

  @impl true
  def run(_input, context) do
    event = %{type: context.signal.type, data: context.signal.data}
    {:ok, %{context.agent_state | events: context.agent_state.events ++ [event]}}
  end
end
