defmodule Jido.Examples.DeduplicatingInbox do
  @moduledoc "An Agent-owned duplicate ledger for input events."

  use Jido.Agent,
    name: "examples_deduplicating_inbox",
    description: "Processes each stable external event ID once"

  agent do
    schema Zoi.object(%{
             seen_event_ids: Zoi.list(Zoi.string()) |> Zoi.default([]),
             processed_items: Zoi.list(Zoi.map()) |> Zoi.default([]),
             processed_count: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0)
           })
  end

  routes do
    signal_source "/examples/deduplicating_inbox"

    route "examples.inbox.event", Jido.Examples.DeduplicatingInbox.Receive do
      define :receive_event
    end
  end
end

defmodule Jido.Examples.DeduplicatingInbox.Receive do
  @moduledoc false
  use Jido.Action,
    name: "examples_deduplicating_inbox_receive",
    schema: Zoi.object(%{event_id: Zoi.string() |> Zoi.min(1), item: Zoi.map()})

  alias Jido.Action.Error

  @impl Jido.Action
  def run(%{event_id: event_id, item: item}, %{agent_state: state}) do
    if event_id in state.seen_event_ids do
      {:error, Error.validation_error("input event was already processed")}
    else
      {:ok,
       %{
         state
         | seen_event_ids: state.seen_event_ids ++ [event_id],
           processed_items: state.processed_items ++ [item],
           processed_count: state.processed_count + 1
       }}
    end
  end
end
