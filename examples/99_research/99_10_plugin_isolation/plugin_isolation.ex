defmodule Jido.Examples.PluginIsolation.First.Agent do
  @moduledoc false
  use Jido.Agent.Plugin

  def observes(_opts), do: []

  def prepare(preparation, _opts),
    do: {:ok, %{preparation | input: "original"}}
end

defmodule Jido.Examples.PluginIsolation.First do
  @moduledoc false
  use Jido.Plugin, agent: Jido.Examples.PluginIsolation.First.Agent
end

defmodule Jido.Examples.PluginIsolation.Audit.Agent do
  @moduledoc "Records the data made available to a Plugin callback. No external work occurs."
  use Jido.Agent.Plugin

  def observes(_opts), do: [:total]

  def prepare(preparation, opts) do
    input = %{
      observed_fields: Map.keys(preparation.agent_state),
      attempted_first_input: if(opts[:replace_input], do: "replaced", else: nil)
    }

    {:ok, %{preparation | input: input}}
  end
end

defmodule Jido.Examples.PluginIsolation.Audit do
  @moduledoc false
  use Jido.Plugin, agent: Jido.Examples.PluginIsolation.Audit.Agent
end

defmodule Jido.Examples.PluginIsolation.Owned.Agent do
  @moduledoc false
  use Jido.Agent.Plugin
  alias Jido.Agent.Plugin.Contribution

  def state_spec(_), do: {:audit, Zoi.integer() |> Zoi.default(0)}

  def contribute(transition, _opts) do
    {:ok,
     %Contribution{plugin: transition.plugin, state: {:replace, transition.plugin_state + 1}}}
  end
end

defmodule Jido.Examples.PluginIsolation.Owned do
  @moduledoc false
  use Jido.Plugin, agent: Jido.Examples.PluginIsolation.Owned.Agent
end

defmodule Jido.Examples.PluginIsolation.Record do
  @moduledoc false
  use Jido.Action, name: "research_plugin_record"

  def run(input, context) do
    inputs = context.plugin_inputs
    audit_input = Map.fetch!(inputs, Jido.Examples.PluginIsolation.Audit)

    state = %{
      context.agent_state
      | observed_fields: audit_input.observed_fields,
        first_input: Map.fetch!(inputs, Jido.Examples.PluginIsolation.First)
    }

    state = if input[:overwrite_owned], do: %{state | audit: 99}, else: state
    {:ok, state}
  end
end

defmodule Jido.Examples.PluginIsolation.ReadAudit do
  @moduledoc "Declares ordered Plugins that read and update their own data."
  use Jido.Agent, name: "research_plugin_read_audit"
  alias Jido.Examples.PluginIsolation.{Audit, First, Owned, Record}

  agent do
    schema Zoi.object(%{
             total: Zoi.integer() |> Zoi.default(10),
             customer_secret: Zoi.string() |> Zoi.default("private"),
             observed_fields: Zoi.list(Zoi.atom()) |> Zoi.default([]),
             first_input: Zoi.string() |> Zoi.default("")
           })

    plugin First
    plugin Audit
    plugin Owned
  end

  routes do
    signal_source "/examples/plugin-isolation"
    route "order.audit", Record
  end
end

defmodule Jido.Examples.PluginIsolation.ReplaceInput do
  @moduledoc "Configures a later Plugin to attempt a foreign input replacement."
  use Jido.Agent, name: "research_plugin_replace_input"
  alias Jido.Examples.PluginIsolation.{Audit, First, Owned, Record}

  agent do
    schema Zoi.object(%{
             total: Zoi.integer() |> Zoi.default(10),
             customer_secret: Zoi.string() |> Zoi.default("private"),
             observed_fields: Zoi.list(Zoi.atom()) |> Zoi.default([]),
             first_input: Zoi.string() |> Zoi.default("")
           })

    plugin First
    plugin Audit, config: [replace_input: true]
    plugin Owned
  end

  routes do
    signal_source "/examples/plugin-isolation"
    route "order.audit", Record
  end
end

defmodule Jido.Examples.PluginIsolation do
  @moduledoc "Proves Plugin projections, owned input, and existing write protection."
  alias __MODULE__.{ReadAudit, ReplaceInput}

  def new(opts \\ []) do
    module = if opts[:replace_input], do: ReplaceInput, else: ReadAudit
    module.new!(id: "audit-order")
  end

  def signal(data \\ %{}),
    do: Jido.Signal.new!("order.audit", data, source: "/examples/plugin-isolation")
end
