defmodule Jido.Examples.Heartbeat do
  @moduledoc """
  Uses the Heartbeat Plugin as an owned periodic input source.
  """

  alias Jido.Plugin.Heartbeat

  defmodule Record do
    @moduledoc false
    use Jido.Action,
      name: "runtime_heartbeat_record",
      schema: Zoi.object(%{kind: Zoi.string() |> Zoi.min(1)})

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
    use Jido.Agent, name: "runtime_heartbeat_default_agent"

    agent do
      schema Zoi.object(%{events: Zoi.list(Zoi.map()) |> Zoi.default([])})
      plugin Heartbeat, config: [interval: 60_000, signal_data: %{kind: "default"}]
    end

    routes do
      route "jido.agent.heartbeat", Jido.Examples.Heartbeat.Record
    end
  end

  defmodule CustomAgent do
    @moduledoc "Receives one application-defined Heartbeat Signal."
    use Jido.Agent, name: "runtime_heartbeat_custom_agent"

    agent do
      schema Zoi.object(%{events: Zoi.list(Zoi.map()) |> Zoi.default([])})

      plugin Heartbeat,
        config: [
          interval: 60_000,
          signal_type: "examples.runtime.heartbeat.custom",
          signal_data: %{kind: "custom"},
          source: "/examples/runtime/heartbeat"
        ]
    end

    routes do
      route "examples.runtime.heartbeat.custom", Jido.Examples.Heartbeat.Record
    end
  end
end
