defmodule Jido.Examples.Guardrails.SupportDesk do
  @moduledoc "Applies ticket policy to stock ReAct."

  alias Jido.Joi
  alias __MODULE__.{CheckScope, CheckTicket, ReadTicket}

  use Jido.Agent, name: "examples_guardrails_support_desk", plugins: [Jido.AI.Agent.Plugin]

  import Jido.AI.Agent.Plugin, only: [ai: 1, reasoning: 2, tools: 1]

  state do
    schema Joi.object(%{
             session: Jido.AI.Thread.Projection.schema(),
             ticket_status: Joi.enum([:open, :resolved, :escalated]) |> Joi.default(:open)
           })
  end

  routes do
    signal_source "/examples/guardrails/support-desk"
  end

  defmodule ReadTicket do
    use Jido.Action,
      name: "read_ticket",
      description: "Read the current support ticket status",
      schema: Joi.object(%{}),
      output_schema: Joi.object(%{status: Joi.atom()})

    @impl true
    def run(_params, %{agent_state: %{ticket_status: status}}), do: {:ok, %{status: status}}
  end

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      limits do
        retries 0
      end
    end

    tools do
      action ReadTicket
    end
  end

  def jido_react_guards, do: %{input: CheckScope, output: CheckTicket}
end

defmodule Jido.Examples.Guardrails.SupportDesk.CheckScope do
  use Jido.Action, name: "support_desk_check_scope"

  @impl true
  def run(%{turn: %{input: input}}, _context) do
    allowed = is_binary(input) and String.contains?(String.downcase(input), ["ticket", "device", "support"])
    {:ok, %{allowed: allowed, reason: "Ask a question about your device or ticket."}}
  end
end

defmodule Jido.Examples.Guardrails.SupportDesk.CheckTicket do
  use Jido.Action, name: "support_desk_check_ticket"

  @impl true
  def run(%{outcome: outcome}, %{agent_state: %{ticket_status: status}}) do
    text = String.downcase(outcome.text)

    allowed =
      is_nil(outcome.output) and
        (status == :resolved or not String.contains?(text, "your ticket is resolved")) and
        (status == :escalated or not String.contains?(text, "your ticket is escalated"))

    {:ok, %{allowed: allowed, reason: "Use a ticket control to change ticket status."}}
  end
end
