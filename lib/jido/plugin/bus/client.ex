defmodule Jido.Plugin.Bus.Client do
  @moduledoc """
  Subscribes an Agent to one `Jido.Signal.Bus` path.

  Normal subscriptions cast matching Signals to the Agent. Durable
  subscriptions call the Agent and acknowledge a Bus record only after its
  Turn commits. A failed Turn is retried and can be delivered more than once.
  One failed record blocks later records for that durable subscription. Agent
  handlers for durable input must be idempotent, normally by Signal id.

      plugins: [
        {Jido.Plugin.Bus.Client,
         bus: :commands,
         path: "orders.**",
         durable: "orders-agent"}
      ]
  """

  use Jido.Plugin

  @impl true
  defdelegate await_ready(runtime, opts), to: Jido.Plugin.Bus.Client.Server

  @impl true
  defdelegate child_spec(init), to: Jido.Plugin.Bus.Client.Server
end
