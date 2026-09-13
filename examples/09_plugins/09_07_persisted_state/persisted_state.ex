defmodule Jido.Examples.Plugins.PersistedState.Agent do
  @moduledoc "An Agent with a Plugin-owned value that has a stored representation."
  use Jido.Agent, name: "persisted_plugin_state"

  agent do
    schema Zoi.object(%{visible: Zoi.integer() |> Zoi.default(0)})
    plugin Jido.Examples.Plugins.PersistedState.Package
  end
end
