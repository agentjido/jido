defmodule Jido.AgentServer.Signal.SensorExit do
  @moduledoc """
  Emitted when a managed sensor runtime exits unexpectedly.

  Delivered to the owning agent as `jido.agent.sensor.exit` after the sensor has
  already been removed from the runtime children map. This lets the agent route
  the lifecycle event to restart, degrade, alert, or ignore without treating the
  sensor as a child agent.

  ## Fields

  - `:tag` - Agent-local tag assigned to the sensor runtime
  - `:pid` - PID of the sensor process that exited
  - `:reason` - Exit reason from the sensor process
  - `:sensor` - Sensor module that was running
  - `:origin` - Origin that started the sensor, such as `:directive` or a plugin
  - `:meta` - Metadata stored with the sensor child info
  """

  use Jido.Signal,
    type: "jido.agent.sensor.exit",
    default_source: "/agent",
    schema:
      Zoi.object(%{
        tag: Zoi.any(description: "Tag assigned to the sensor runtime"),
        pid: Zoi.any(description: "PID of the sensor process that exited"),
        reason: Zoi.any(description: "Exit reason from the sensor process"),
        sensor: Zoi.any(description: "Sensor module that was running"),
        origin: Zoi.any(description: "Origin that started the sensor"),
        meta: Zoi.map(description: "Metadata stored with the sensor") |> Zoi.default(%{})
      })
end
