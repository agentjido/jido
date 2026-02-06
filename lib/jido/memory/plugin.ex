defmodule Jido.Memory.Plugin do
  @moduledoc """
  Default singleton plugin for memory state management.

  Declares ownership of the `:__memory__` state key in agent state.
  This plugin does not initialize memory by default — memory is
  created on demand via `Jido.Memory.Agent.ensure/2`.

  ## Singleton

  This plugin is a singleton — it cannot be aliased or duplicated.
  It is automatically included as a default plugin for all agents
  unless explicitly disabled:

      use Jido.Agent,
        name: "minimal",
        default_plugins: %{__memory__: false}

  ## State Key

  Memory is stored at `agent.state[:__memory__]` as a `Jido.Memory` struct.
  Access helpers are provided by `Jido.Memory.Agent`.

  ## Persistence

  This bare-minimum default plugin keeps memory in-process only and
  does not externalize on checkpoint. If you need persistence (ETS,
  database, etc.), implement your own memory plugin with custom
  `on_checkpoint/2` and `on_restore/2` callbacks.
  """

  use Jido.Plugin,
    name: "memory",
    state_key: :__memory__,
    actions: [],
    singleton: true,
    description: "Memory state management for agent cognitive state.",
    capabilities: [:memory]

  @impl Jido.Plugin
  def mount(_agent, _config), do: {:ok, nil}

  @impl Jido.Plugin
  def on_checkpoint(_state, _ctx), do: :keep
end
