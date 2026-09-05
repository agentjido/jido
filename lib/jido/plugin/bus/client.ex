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

  alias Jido.Plugin.Bus.Client.Runtime
  alias Jido.Plugin.Init

  @impl Jido.Plugin
  def await_ready(runtime, opts) do
    GenServer.call(runtime, :await_ready, Keyword.get(opts, :timeout, 5_000))
  catch
    :exit, reason -> {:error, {:bus_client_runtime_unavailable, reason}}
  end

  @doc false
  def child_spec(%Init{} = init) do
    Supervisor.child_spec({Runtime, init}, id: __MODULE__)
  end
end
