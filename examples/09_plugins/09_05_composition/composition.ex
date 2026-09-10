defmodule Jido.Examples.Plugins.Composition.Agent do
  @moduledoc "Combines one pure input Plugin with one live input Plugin."
  use Jido.Agent, name: "plugin_composition_agent"

  agent do
    schema Zoi.object(%{
             accepted: Zoi.integer() |> Zoi.default(0),
             owner: Zoi.string() |> Zoi.default("")
           })

    plugin Jido.Examples.Plugins.PreparedInput.Plugin,
      config: [subject_prefix: "tenant/"]

    plugin Jido.Examples.Plugins.RuntimeAdmission.Plugin,
      config: [tokens: [{"allow", "operator"}]]
  end

  routes do
    signal_source "/examples/plugins/composition"

    route "examples.plugins.composition.accept" do
      action %{token: _token}, schema: Zoi.object(%{token: Zoi.string()}), context: context do
        tenant = context.plugin_inputs[Jido.Examples.Plugins.PreparedInput.Plugin]
        authorization = context.plugin_inputs[Jido.Examples.Plugins.RuntimeAdmission.Plugin]

        {:ok,
         %{
           context.agent_state
           | accepted: context.agent_state.accepted + 1,
             owner: tenant.tenant <> ":" <> authorization.principal
         }}
      end
    end
  end
end
