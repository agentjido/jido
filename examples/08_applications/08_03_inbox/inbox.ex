defmodule Jido.Examples.Applications.Inbox.Agent do
  @moduledoc "Accepts unique events from a managed, tagged input sensor."
  use Jido.Agent, name: "application_inbox_agent"

  alias Jido.Examples.Applications.Inbox.Sensor
  alias Jido.Plugin.SensorManager

  agent do
    schema Zoi.object(%{
             accepted: Zoi.integer() |> Zoi.default(0),
             seen: Zoi.list(Zoi.string()) |> Zoi.default([])
           })

    plugin SensorManager, config: [retry_delay_ms: 10]
  end

  routes do
    signal_source "/examples/applications/inbox"
    route "examples.applications.inbox.sensor", __MODULE__.ManageSensor, as: :sensor

    route "examples.applications.inbox.event", as: :event do
      action %{event_id: event_id},
        schema: Zoi.object(%{event_id: Zoi.string() |> Zoi.min(1)}),
        context: context do
        if event_id in context.agent_state.seen do
          {:ok, context.agent_state}
        else
          {:ok,
           %{
             context.agent_state
             | seen: context.agent_state.seen ++ [event_id],
               accepted: context.agent_state.accepted + 1
           }}
        end
      end
    end
  end

  defmodule ManageSensor do
    @moduledoc false
    use Jido.Action,
      name: "application_inbox_manage_sensor",
      schema:
        Zoi.object(%{
          operation: Zoi.enum([:start, :stop]),
          tag: Zoi.string() |> Zoi.min(1)
        })

    def run(%{operation: :start, tag: tag}, context) do
      directive =
        SensorManager.start(tag, Sensor, %{
          source: "/examples/applications/inbox/#{tag}"
        })

      {:ok, context.agent_state, [directive]}
    end

    def run(%{operation: :stop, tag: tag}, context) do
      {:ok, context.agent_state, [SensorManager.stop(tag)]}
    end
  end
end
