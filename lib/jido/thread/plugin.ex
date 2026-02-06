defmodule Jido.Thread.Plugin do
  @moduledoc """
  Default singleton plugin for thread state management.

  Declares ownership of the `:__thread__` state key in agent state.
  This plugin does not initialize a thread by default — threads are
  created on demand via `Jido.Thread.Agent.ensure/2`.

  ## Singleton

  This plugin is a singleton — it cannot be aliased or duplicated.
  It is automatically included as a default plugin for all agents
  unless explicitly disabled:

      use Jido.Agent,
        name: "minimal",
        default_plugins: %{__thread__: false}

  ## State Key

  The thread is stored at `agent.state[:__thread__]` as a `Jido.Thread` struct.
  Access helpers are provided by `Jido.Thread.Agent`.
  """

  use Jido.Plugin,
    name: "thread",
    state_key: :__thread__,
    actions: [],
    singleton: true,
    description: "Thread state management for agent conversation history.",
    capabilities: [:thread]

  alias Jido.Thread

  @impl Jido.Plugin
  def mount(_agent, _config), do: {:ok, nil}

  @impl Jido.Plugin
  def on_checkpoint(%Thread{id: id, rev: rev}, _ctx) do
    {:externalize, :thread, %{id: id, rev: rev}}
  end

  def on_checkpoint(nil, _ctx), do: :keep

  @impl Jido.Plugin
  def on_restore(_pointer, _ctx), do: {:ok, nil}
end
