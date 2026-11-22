defmodule Jido.Examples.Plugins.Composition.Agent do
  @moduledoc "Combines one pure input Plugin with one live input Plugin."

  alias Jido.Joi

  use Jido.Agent,
    name: "plugin_composition_agent",
    plugins: [
      {Jido.Examples.Plugins.Composition.Tenant, %{subject_prefix: "tenant/"}},
      {Jido.Examples.Plugins.Composition.Authorization, %{tokens: [{"allow", "operator"}]}}
    ]

  state do
    schema Joi.object(%{
             accepted: Joi.integer() |> Joi.default(0),
             owner: Joi.string() |> Joi.default("")
           })
  end

  routes do
    signal_source "/examples/plugins/composition"

    route "examples.plugins.composition.accept" do
      action %{token: _token},
        schema: Joi.object(%{token: Joi.string()}),
        context: context do
        tenant = context.plugin_inputs[Jido.Examples.Plugins.Composition.Tenant].prepared

        authorization =
          context.plugin_inputs[Jido.Examples.Plugins.Composition.Authorization].runtime

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
