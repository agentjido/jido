defmodule Jido.Plugin.Bus.Manager do
  @moduledoc """
  Starts and owns one `Jido.Signal.Bus` for an Agent.

  The Bus uses the Agent ID as its name by default. Set `:name` when callers
  need another stable name. The Agent's Jido instance is the default Bus scope;
  set `jido: nil` for a global Bus.

      plugins: [
        {Jido.Plugin.Bus.Manager, name: :orders}
      ]

  The Bus stops with its Agent. The default memory store does not survive a Bus
  or Agent restart. Configure a persistent `Jido.Signal.Bus.Store` when records
  and durable subscription cursors must survive that lifecycle.

  When one Agent owns and consumes the same Bus, declare `Manager` before
  `Jido.Plugin.Bus.Client` so the Bus exists before the Client starts.
  """

  use Jido.Plugin, agent_server: Jido.Plugin.Bus.Manager.Server
end
