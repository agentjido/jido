defmodule Jido.Examples.Persistence.PluginStateConversion.Agent do
  @moduledoc "An Agent with a Plugin-owned value that has a stored representation."

  alias Jido.Joi

  use Jido.Agent,
    name: "persisted_plugin_state",
    plugins: [Jido.Examples.Persistence.PluginStateConversion.Package]

  state do
    schema Joi.object(%{visible: Joi.integer() |> Joi.default(0)})
  end
end
