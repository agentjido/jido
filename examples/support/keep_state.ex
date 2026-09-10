defmodule Jido.Examples.Support.KeepState do
  @moduledoc "A shared no-op Action for lifecycle Signals that need no state change."

  use Jido.Action, name: "examples_keep_state"

  @impl true
  def run(_input, %{agent_state: state}), do: {:ok, state}
end
