Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("support_desk.ex", __DIR__)

defmodule Jido.Examples.Guardrails.SupportDeskTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.Examples.Guardrails.SupportDesk
  alias Jido.Examples.Support.OfflineInferenceClient

  test "ticket status controls which model claims the stock recipe accepts" do
    open_ticket = SupportDesk.instantiate!(id: "open-ticket")
    resolved_ticket = SupportDesk.instantiate!(id: "resolved-ticket", state: %{ticket_status: :resolved})
    claim = "Your ticket is resolved."

    assert %{status: :blocked, reason_code: :input} = request(open_ticket, "Give me a stock price", claim)
    assert %{status: :blocked} = request(open_ticket, "Help with my ticket", claim)
    assert %{status: :completed, output: ^claim} = request(resolved_ticket, "Help with my ticket", claim)
  end

  defp request(agent, input, response) do
    signal = SupportDesk.request_signal!(%{input: input, options: %{offline_response: response}})
    context = %{jido_ai_inference_client: OfflineInferenceClient}

    assert {:ok, _agent, [%Jido.Agent.Directive.Reply{signal: reply}]} =
             SupportDesk.cmd(agent, signal, context: context)

    reply.data
  end
end
