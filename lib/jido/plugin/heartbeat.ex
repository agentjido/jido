defmodule Jido.Plugin.Heartbeat do
  @moduledoc """
  Sends a periodic Signal to its Agent.

  This is a small example of an input Plugin. The Plugin runtime owns the
  timer. Each tick enters the Agent through its normal Signal mailbox.

      plugins: [
        {Jido.Plugin.Heartbeat,
         interval: 1_000,
         signal_type: "system.heartbeat",
         signal_data: %{source: :clock}}
      ]
  """

  use Jido.Plugin

  alias Jido.Plugin.Heartbeat.Runtime
  alias Jido.Plugin.Init

  @doc false
  def child_spec(%Init{} = init) do
    Supervisor.child_spec({Runtime, init}, id: __MODULE__)
  end
end
