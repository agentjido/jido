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

  use Jido.Plugin,
    option_keys: [
      agent_server: [:bus, :durable, :jido, :path, :retry_delay_ms, :start_from, :timeout]
    ]

  alias Jido.Signal.Bus

  @typedoc "A durable subscription starting position."
  @type start_position :: :origin | :current | non_neg_integer()

  @typedoc "One Client Plugin option."
  @type option ::
          {:bus, Bus.server()}
          | {:durable, Bus.durable_id() | nil}
          | {:jido, atom() | nil}
          | {:path, Bus.path()}
          | {:retry_delay_ms, pos_integer()}
          | {:start_from, start_position() | nil}
          | {:timeout, pos_integer()}

  @impl true
  defdelegate await_ready(runtime, opts), to: Jido.Plugin.Bus.Client.Server

  @impl true
  defdelegate child_spec(init), to: Jido.Plugin.Bus.Client.Server
end
