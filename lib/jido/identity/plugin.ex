defmodule Jido.Identity.Plugin do
  @moduledoc """
  Default singleton plugin for identity state management.
  Declares ownership of the `:__identity__` state key in agent state.
  This plugin does not initialize an identity by default — identities are
  created on demand via `Jido.Identity.Agent.ensure/2`.

  ## Singleton
  This plugin is a singleton — it cannot be aliased or duplicated.
  It is automatically included as a default plugin for all agents
  unless explicitly disabled:

      use Jido.Agent,
        name: "minimal",
        default_plugins: %{__identity__: false}

  ## State Key
  The identity is stored at `agent.state[:__identity__]` as a `Jido.Identity` struct.
  Access helpers are provided by `Jido.Identity.Agent` and related modules.
  """

  use Jido.Plugin,
    name: "identity",
    state_key: :__identity__,
    actions: [],
    singleton: true,
    description: "Identity state management for agent self-model.",
    capabilities: [:identity]

  @impl Jido.Plugin
  def mount(_agent, _config), do: {:ok, nil}
end
