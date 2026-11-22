defmodule Jido.Examples.Patterns.SupportDesk do
  @moduledoc "Owns a ticket and its approved conversation."

  alias Jido.Joi
  alias __MODULE__.{CheckReply, Reasoning, SetStatus, Troubleshoot}

  use Jido.Agent, name: "examples_application_support_desk", plugins: [Jido.AI.Agent.Plugin]

  import Jido.AI.Agent.Plugin, only: [ai: 1, reasoning: 2, tools: 1]

  state do
    schema Joi.object(%{
             session: Jido.AI.Thread.Projection.schema(),
             ticket_status: Joi.enum([:open, :resolved, :escalated]) |> Joi.default(:open)
           })
  end

  routes do
    signal_source "/examples/application/support-desk"
    route "examples.support_desk.ticket.update", SetStatus, as: :update_ticket
  end

  ai do
    reasoning Reasoning do
      instructions "Give one verified support step. Use ticket controls for status changes."
    end

    tools do
      action Troubleshoot
    end
  end

  def jido_react_guards, do: %{output: CheckReply}

  defmodule Troubleshoot do
    use Jido.Action,
      name: "troubleshoot_printer",
      description: "Look up the next verified support step for an offline printer",
      schema: Joi.object(%{})

    @impl true
    def run(_params, _context), do: {:ok, %{next_step: "Check the printer cable."}}
  end

  defmodule CheckReply do
    use Jido.Action, name: "examples_application_support_desk_check_reply"

    @impl true
    def run(%{outcome: %{text: text}}, %{agent_state: %{ticket_status: status}}) do
      text = String.downcase(text || "")

      allowed =
        not String.contains?(text, ["i resolved", "i escalated"]) and
          (status == :resolved or not String.contains?(text, "your ticket is resolved")) and
          (status == :escalated or not String.contains?(text, "your ticket is escalated"))

      {:ok, %{allowed: allowed, reason: "Use a ticket control to change ticket status."}}
    end
  end

  defmodule SetStatus do
    use Jido.Action,
      name: "examples_support_desk_set_status",
      schema: Joi.object(%{ticket_status: Joi.enum([:resolved, :escalated])})

    @impl true
    def run(%{ticket_status: status}, %{agent_state: state}), do: {:ok, %{state | ticket_status: status}}
  end
end
