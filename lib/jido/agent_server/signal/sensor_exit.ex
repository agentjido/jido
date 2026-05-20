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
    extension_policy: [
      {Jido.Signal.Ext.Trace, :optional},
      {Jido.Signal.Ext.Dispatch, :optional}
    ],
    schema: [
      tag: [type: :any, required: true, doc: "Tag assigned to the sensor runtime"],
      pid: [type: :any, required: true, doc: "PID of the sensor process that exited"],
      reason: [type: :any, required: true, doc: "Exit reason from the sensor process"],
      sensor: [type: :any, required: true, doc: "Sensor module that was running"],
      origin: [type: :any, required: true, doc: "Origin that started the sensor"],
      meta: [type: :map, default: %{}, doc: "Metadata stored with the sensor"]
    ]
end
