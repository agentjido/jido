defmodule Jido.Examples.Applications.Inbox.Agent do
  @moduledoc "Accepts unique events delivered by an input Plugin runtime."
  use Jido.Agent, name: "application_inbox_agent"

  agent do
    schema Zoi.object(%{
             accepted: Zoi.integer() |> Zoi.default(0),
             seen: Zoi.list(Zoi.string()) |> Zoi.default([])
           })

    plugin Jido.Examples.Applications.Inbox.Plugin
  end

  routes do
    signal_source "/examples/applications/inbox"

    route "examples.applications.inbox.event" do
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
end
