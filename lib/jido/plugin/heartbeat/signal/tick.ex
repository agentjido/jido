defmodule Jido.Plugin.Heartbeat.Signal.Tick do
  @moduledoc "The default periodic Signal sent by the Heartbeat Plugin."

  use Jido.Signal,
    type: "jido.agent.heartbeat",
    default_source: "/plugin/heartbeat",
    schema: Zoi.map()
end
