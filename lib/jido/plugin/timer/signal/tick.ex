defmodule Jido.Plugin.Timer.Signal.Tick do
  @moduledoc "The default periodic Signal sent by a static Timer interval."

  use Jido.Signal,
    type: "jido.agent.heartbeat",
    default_source: "/plugin/heartbeat",
    schema: Jido.Joi.map()
end
