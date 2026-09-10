defmodule Jido.Examples.Plugins.PreparedInput.Plugin do
  @moduledoc "Prepares one portable tenant input without changing the Signal."

  use Jido.Plugin,
    agent: Jido.Examples.Plugins.PreparedInput.Plugin.Agent,
    option_keys: [agent: [:subject_prefix]]
end

defmodule Jido.Examples.Plugins.PreparedInput.Plugin.Agent do
  @moduledoc false
  use Jido.Agent.Plugin

  alias Jido.Agent.Plugin.Preparation

  @impl true
  def prepare(%Preparation{signal: signal}, opts) do
    prefix = Keyword.fetch!(opts, :subject_prefix)

    subject = signal.subject

    if is_binary(subject) and String.starts_with?(subject, prefix) do
      case String.replace_prefix(subject, prefix, "") do
        "" -> {:error, :tenant_subject_required}
        tenant -> {:ok, %{tenant: String.downcase(tenant), signal_id: signal.id}}
      end
    else
      {:error, :tenant_subject_required}
    end
  end
end

defmodule Jido.Examples.Plugins.PreparedInput.Agent do
  @moduledoc "Uses portable data prepared from the unchanged source Signal."
  use Jido.Agent, name: "plugin_prepared_input_agent"

  agent do
    schema Zoi.object(%{
             accepted: Zoi.integer() |> Zoi.default(0),
             last_signal_id: Zoi.string() |> Zoi.default(""),
             last_subject: Zoi.string() |> Zoi.default(""),
             tenant: Zoi.string() |> Zoi.default("")
           })

    plugin Jido.Examples.Plugins.PreparedInput.Plugin,
      config: [subject_prefix: "tenant/"]
  end

  routes do
    signal_source "/examples/plugins/prepared_input"

    route "examples.plugins.prepared_input.accept" do
      action _input, schema: Zoi.object(%{}), context: context do
        prepared = context.plugin_inputs[Jido.Examples.Plugins.PreparedInput.Plugin].prepared

        {:ok,
         %{
           context.agent_state
           | accepted: context.agent_state.accepted + 1,
             last_signal_id: prepared.signal_id,
             last_subject: context.signal.subject,
             tenant: prepared.tenant
         }}
      end
    end
  end
end
