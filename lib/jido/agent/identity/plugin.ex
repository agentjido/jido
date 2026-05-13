defmodule Jido.Agent.Identity.Plugin do
  @moduledoc """
  Default singleton plugin for agent identity state management.

  Declares ownership of the `:__identity__` state key in agent state.
  This plugin does not initialize an identity by default; identities are
  created on demand via `Jido.Agent.Identity.Agent.ensure/2`.

  ## Singleton
  This plugin is a singleton — it cannot be aliased or duplicated.
  It is automatically included as a default plugin for all agents
  unless explicitly disabled:

      use Jido.Agent,
        name: "minimal",
        default_plugins: %{__identity__: false}

  ## State Key
  The identity is stored at `agent.state[:__identity__]` as a
  `Jido.Agent.Identity` struct. This plugin keeps the existing `identity`
  metadata name and `:identity` capability because plugin ownership remains
  anchored on the canonical `:__identity__` state key.
  """

  use Jido.Plugin,
    name: "identity",
    state_key: :__identity__,
    actions: [],
    singleton: true,
    description: "Agent identity state management for profile and lifecycle facts.",
    capabilities: [:identity]

  @impl Jido.Plugin
  def mount(_agent, _config), do: {:ok, nil}
end
