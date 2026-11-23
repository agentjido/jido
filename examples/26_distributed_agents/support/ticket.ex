defmodule Jido.Examples.DistributedAgents.Ticket do
  @moduledoc "A support ticket that records an approval or a missed deadline."

  alias Jido.Agent.Address
  alias Jido.AgentServer.Pending
  alias Jido.{Joi, Signal}

  use Jido.Agent, name: "distributed_support_ticket"

  @signal_source "/examples/distribution/support"

  state do
    schema Joi.object(%{
             status: Joi.enum([:open, :approved, :escalated]) |> Joi.default(:open),
             last_note: Joi.string() |> Joi.nullable() |> Joi.default(nil)
           })
  end

  routes do
    route "examples.distribution.ticket.open", __MODULE__.Deadline, as: :open do
    end

    route "examples.distribution.ticket.note", as: :note do
      action %{text: text},
        schema: Joi.object(%{text: Joi.string() |> Joi.min(1)}),
        context: context do
        {:ok, %{context.agent_state | last_note: text}}
      end
    end
  end

  @doc "Opens the ticket's approval Turn and retains its eventual result for pickup by Address."
  def open(instance, %Address{} = address) do
    signal = Signal.new!("examples.distribution.ticket.open", %{ticket_id: address.id}, source: @signal_source)

    with %Pending{} = pending <- Jido.submit(instance, address, signal, result_handoff: true) do
      Jido.AgentServer.await(pending, 5_000)
    end
  end

  @doc "Builds an approval Signal for one ticket."
  def approve(ticket_id) do
    Signal.new!("examples.distribution.ticket.approve", %{ticket_id: ticket_id}, source: @signal_source)
  end

  @doc "Builds a Signal that records a note on an open ticket."
  def note(text), do: Signal.new!("examples.distribution.ticket.note", %{text: text}, source: @signal_source)
end

defmodule Jido.Examples.DistributedAgents.Ticket.Deadline do
  @moduledoc "Waits for approval until the ticket reaches its deadline."

  alias Jido.Joi

  use Jido.Flow,
    name: "distributed_support_ticket_deadline",
    schema: Joi.object(%{ticket_id: Joi.string() |> Joi.min(1)})

  flow do
    selection "decision" do
      await "approved", event: "examples.distribution.ticket.approve", match: %{ticket_id: input(:ticket_id)}
      timer "escalated", after_ms: 5_000
    end

    step "record", decision <- result("decision"), inline: [context: context] do
      status =
        case decision.selected do
          "approved" -> :approved
          "escalated" -> :escalated
        end

      {:ok, %{context.agent_state | status: status}}
    end

    output result("record")
  end
end
