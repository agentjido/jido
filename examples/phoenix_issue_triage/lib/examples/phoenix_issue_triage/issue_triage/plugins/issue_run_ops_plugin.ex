defmodule Examples.PhoenixIssueTriage.IssueTriage.Plugins.IssueRunOpsPlugin do
  @moduledoc """
  Pod-level operations plugin that owns sensor subscriptions and runtime ops state.
  """

  use Jido.Plugin,
    name: "issue_run_ops",
    state_key: :ops,
    actions: [],
    schema:
      Zoi.object(
        %{
          heartbeat_count: Zoi.integer() |> Zoi.default(0),
          webhook_event_count: Zoi.integer() |> Zoi.default(0),
          last_heartbeat_at: Zoi.any() |> Zoi.optional(),
          last_heartbeat_message: Zoi.string() |> Zoi.default(""),
          last_webhook_event: Zoi.string() |> Zoi.default(""),
          last_signal_source: Zoi.string() |> Zoi.default("")
        },
        coerce: true
      ),
    subscriptions: [
      {Jido.Sensors.Heartbeat, %{interval: 100, message: "issue-run-alive"}},
      {Examples.PhoenixIssueTriage.IssueTriage.Sensors.IssueWebhookSensor,
       %{source_path: "/phoenix/webhooks/issues"}}
    ],
    capabilities: [:workflow_ops, :subscriptions]
end
