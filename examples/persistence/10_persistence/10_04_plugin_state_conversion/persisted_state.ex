defmodule Jido.Examples.Persistence.PluginStateConversion.Agent do
  @moduledoc "An Agent with a Plugin-owned value that has a stored representation."
  use Jido.Agent,
    name: "persisted_plugin_state",
    plugins: [Jido.Examples.Persistence.PluginStateConversion.Package]

  state do
    schema Jido.Joi.object(%{visible: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end
end
