defmodule Examples.PhoenixIssueTriage.IssueTriage.Actions.TrackHeartbeatAction do
  @moduledoc false

  use Jido.Action,
    name: "track_heartbeat",
    schema: [
      message: [type: :string, default: "heartbeat"],
      timestamp: [type: :any, required: false]
    ]

  alias Examples.PhoenixIssueTriage.IssueTriage.Artifacts
  alias Jido.Agent.StateOp
  alias Jido.Thread.Agent, as: ThreadAgent

  def run(%{message: message, timestamp: timestamp}, %{state: state, agent: agent}) do
    updated_agent =
      ThreadAgent.append(agent, %{
        kind: :heartbeat,
        payload: %{message: message, timestamp: timestamp}
      })

    heartbeat_count = get_in(state, [:ops, :heartbeat_count]) || 0

    {:ok, %{},
     [
       StateOp.set_path([:ops, :heartbeat_count], heartbeat_count + 1),
       StateOp.set_path([:ops, :last_heartbeat_message], message),
       StateOp.set_path([:ops, :last_heartbeat_at], timestamp),
       StateOp.set_path([:ops, :last_signal_source], "/sensor/heartbeat")
       | Artifacts.artifact_ops(updated_agent)
     ]}
  end
end
