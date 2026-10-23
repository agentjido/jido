defmodule Jido.Examples.LivePluginChanges do
  @moduledoc "Installs, reconfigures, and removes one state-owning runtime Plugin."
  use Jido.Agent, name: "live_plugin_changes"
  alias Jido.Agent.Directive, as: D
  alias Jido.Examples.LivePluginChanges.Cache

  routes do
    signal_source "/examples/plugins/live_changes"

    route "examples.plugins.live_changes.install", as: :install do
      action _input, context: context, output_schema: Zoi.map() do
        {:ok, context.agent_state, [D.plugin_add(Cache, capacity: 2)]}
      end

      state(from: output())
    end

    route "examples.plugins.live_changes.configure", as: :configure do
      action %{capacity: capacity},
        schema: Zoi.object(%{capacity: Zoi.integer()}),
        context: context,
        output_schema: Zoi.map() do
        {:ok, context.agent_state, [D.plugin_configure(Cache, capacity: capacity)]}
      end

      state(from: output())
    end

    route "examples.plugins.live_changes.refresh", as: :refresh do
      action _input, context: context, output_schema: Zoi.map() do
        {:ok, context.agent_state}
      end

      state(from: output())
    end

    route "examples.plugins.live_changes.remove", as: :remove do
      action %{discard: discard},
        schema: Zoi.object(%{discard: Zoi.boolean()}),
        context: context,
        output_schema: Zoi.map() do
        options = if discard, do: [state: :discard], else: []
        {:ok, context.agent_state, [D.plugin_remove(Cache, options)]}
      end

      state(from: output())
    end
  end
end
