defmodule Jido.Examples.PluginIsolation.First do
  @moduledoc false
  use Jido.Plugin

  def prepare(command, _opts),
    do: {:ok, %{command | context: Map.put(command.context, :first_input, "original")}}
end

defmodule Jido.Examples.PluginIsolation.Audit do
  @moduledoc "Records the data made available to a Plugin callback. No external work occurs."
  use Jido.Plugin

  def prepare(command, opts) do
    context = Map.put(command.context, :observed_fields, Map.keys(command.agent.state))

    context =
      if opts[:replace_input], do: Map.put(context, :first_input, "replaced"), else: context

    {:ok, %{command | context: context}}
  end
end

defmodule Jido.Examples.PluginIsolation.Owned do
  @moduledoc false
  use Jido.Plugin
  def state_spec(_), do: {:audit, Zoi.integer() |> Zoi.default(0)}
  def update_state(value, _, _), do: {:ok, value + 1}
end

defmodule Jido.Examples.PluginIsolation.Record do
  @moduledoc false
  use Jido.Action, name: "research_plugin_record"

  def run(input, context) do
    state = %{
      context.agent_state
      | observed_fields: context.observed_fields,
        first_input: context.first_input
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
  @moduledoc "Configures a later Plugin to replace an earlier Plugin's input."
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
  @moduledoc "Tests Plugin data access, prepared input ownership, and existing write protection."
  alias __MODULE__.{ReadAudit, ReplaceInput}

  def new(opts \\ []) do
    module = if opts[:replace_input], do: ReplaceInput, else: ReadAudit
    module.new!(id: "audit-order")
  end

  def signal(data \\ %{}),
    do: Jido.Signal.new!("order.audit", data, source: "/examples/plugin-isolation")
end
