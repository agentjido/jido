defmodule Jido.Examples.Heartbeat do
  @moduledoc """
  Uses a static Timer interval as an owned periodic input source.
  """

  alias Jido.Plugin.Timer

  defmodule Record do
    @moduledoc false

    alias Jido.Joi

    use Jido.Action,
      name: "runtime_heartbeat_record",
      schema: Joi.object(%{kind: Joi.string() |> Joi.min(1)})

    def run(input, context) do
      event = %{
        type: context.signal.type,
        source: context.signal.source,
        data: input
      }

      {:ok, %{context.agent_state | events: context.agent_state.events ++ [event]}}
    end
  end

  defmodule DefaultAgent do
    @moduledoc "Receives the default Heartbeat Signal."

    alias Jido.Joi

    use Jido.Agent,
      name: "runtime_heartbeat_default_agent",
      plugins: [{Timer, %{interval: 20, signal_data: %{kind: "default"}}}]

    state do
      schema Joi.object(%{events: Joi.list(Joi.map()) |> Joi.default([])})
    end

    routes do
      route "jido.agent.heartbeat", Jido.Examples.Heartbeat.Record
    end
  end

  defmodule CustomAgent do
    @moduledoc "Receives one application-defined Heartbeat Signal."

    alias Jido.Joi

    use Jido.Agent,
      name: "runtime_heartbeat_custom_agent",
      plugins: [
        {Timer,
         %{
           interval: 20,
           signal_type: "examples.runtime.heartbeat.custom",
           signal_data: %{kind: "custom"},
           source: "/examples/runtime/heartbeat"
         }}
      ]

    state do
      schema Joi.object(%{events: Joi.list(Joi.map()) |> Joi.default([])})
    end

    routes do
      route "examples.runtime.heartbeat.custom", Jido.Examples.Heartbeat.Record
    end
  end
end
