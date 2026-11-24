# Parent and Child Agents

Declare a topology when one Agent owns a fixed set of members. The parent and each member have their own state and commit their own Turns. Jido starts the members with the parent and stops them when the parent stops.

When a request determines which Agents to start, [start them from application code](../agent-servers/child-agents-and-adoption.md) and manage their lifetimes by ID.

## Send work to a member

This triage Agent forwards a ticket to its summarizer. The summarizer emits its result, and a topology connection sends the result to the parent.

```elixir
defmodule TriageGuide.Summarizer do
  use Jido.Agent, name: "ticket_summarizer"

  routes do
    route "ticket.opened" do
      transform %Jido.Signal{data: %{words: words}} do
        Jido.Signal.new("ticket.summarized", %{words: div(words, 2)}, source: "/tickets/summarizer")
      end
    end
  end
end

defmodule TriageGuide.Triage do
  use Jido.Agent, name: "ticket_triage"

  state do
    schema Jido.Joi.object(%{
             summary_words: Jido.Joi.integer() |> Jido.Joi.default(0)
           })
  end

  routes do
    signal_source "/tickets/triage"

    route "ticket.opened", as: :open do
      forward(to: agent(:summarizer))
    end

    route "ticket.summarized" do
      action %{words: words},
        schema: Jido.Joi.object(%{words: Jido.Joi.integer()}),
        context: context do
        {:ok, %{context.agent_state | summary_words: words}}
      end
    end
  end

  topology do
    agent :summarizer, TriageGuide.Summarizer

    connections do
      connect "ticket.summarized", from: :summarizer, to: :root
    end
  end
end

instance = TriageGuide.Jido
{:ok, _instance} = Jido.start(name: instance)
{:ok, triage} = Jido.start_agent(instance, TriageGuide.Triage, id: "triage-1")
:ok = Jido.AgentServer.await_ready(triage)

{:ok, opened} = TriageGuide.Triage.open_signal(%{words: 300})
{:ok, %{status: :committed}} = Jido.AgentServer.call(triage, opened)
```

The call confirms the parent's first Turn. The member processes the ticket separately. Check the parent's snapshot to see when the result arrives.

```elixir
true =
  Enum.any?(1..200, fn _attempt ->
    Process.sleep(10)
    Jido.AgentServer.snapshot(triage).agent.state.summary_words == 150
  end)
```

## Stop one declared member

Use the member name and its one-based slot with `Jido.AgentServer.remove_topology_member/4`. This drains that slot and stops its subtree. The parent stays active. A new activation of the parent starts the declared member again.

```elixir
2 = Jido.resident_agent_count(instance)
:ok = Jido.AgentServer.remove_topology_member(triage, :summarizer, 1)
1 = Jido.resident_agent_count(instance)
:ok = Jido.stop_agent(instance, triage)
```

See [Connect Agent Outputs](connect-agent-outputs.livemd) for more routing examples.
