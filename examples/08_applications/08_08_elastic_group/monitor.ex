defmodule Jido.Examples.Applications.ElasticGroup.MonitorAgent do
  @moduledoc "Records public control events without participating in group decisions."
  use Jido.Agent, name: "elastic_group_monitor"

  agent do
    schema Zoi.object(%{
             group_id: Zoi.string() |> Zoi.default(""),
             generation: Zoi.integer() |> Zoi.default(0),
             events: Zoi.list(Zoi.string()) |> Zoi.default([]),
             counts: Zoi.map() |> Zoi.default(%{})
           })

    plugin Jido.Examples.Applications.BusInput,
      config: [bus: :elastic_group_bus, paths: ["examples.applications.elastic_group.control.**"]]
  end

  routes do
    signal_source "/examples/applications/elastic_group/monitor"

    route "examples.applications.elastic_group.control.**" do
      action _input,
        schema:
          Zoi.object(%{
            group_id: Zoi.string(),
            generation: Zoi.integer(),
            member_id: Zoi.string()
          }),
        context: context do
        state = context.agent_state
        type = context.signal.type

        {:ok,
         %{
           state
           | events: state.events ++ [type],
             counts: Map.update(state.counts, type, 1, &(&1 + 1))
         }}
      end
    end
  end
end
