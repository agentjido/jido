defmodule JidoTest.Authoring.Agents.Fixtures.ExtensionRoute do
  use Jido.Agent,
    name: "authoring_extension_route",
    extensions: [JidoTest.Authoring.Agents.Fixtures.ViaExtension]

  agent do
    schema Zoi.object(%{text: Zoi.string() |> Zoi.default("")})
  end

  routes do
    signal_source "/authoring/extension_route"

    route "text.write", via: JidoTest.Authoring.Agents.Fixtures.SetText do
      define :write, args: [:text]
    end
  end
end
