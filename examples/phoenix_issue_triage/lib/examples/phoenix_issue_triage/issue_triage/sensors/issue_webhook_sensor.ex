defmodule Examples.PhoenixIssueTriage.IssueTriage.Sensors.IssueWebhookSensor do
  @moduledoc """
  Converts webhook-style issue events into Jido signals for the pod manager.
  """

  use Jido.Sensor,
    name: "issue_webhook_sensor",
    description: "Receives Phoenix webhook events and emits issue intake signals",
    schema:
      Zoi.object(
        %{
          source_path:
            Zoi.string(description: "Logical source for emitted signals")
            |> Zoi.default("/phoenix/webhooks/issues")
        },
        coerce: true
      )

  @impl Jido.Sensor
  def init(config, _context) do
    {:ok, %{source_path: config.source_path, received_count: 0}}
  end

  @impl Jido.Sensor
  def handle_event({event_type, payload}, state) when is_map(payload) do
    signal =
      Jido.Signal.new!(
        "issue.webhook.received",
        Map.put(payload, :event_type, to_string(event_type)),
        source: state.source_path
      )

    {:ok, %{state | received_count: state.received_count + 1}, [{:emit, signal}]}
  end
end
