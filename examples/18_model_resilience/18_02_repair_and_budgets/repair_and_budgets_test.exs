Code.require_file("../support/scripted_inference_client.ex", __DIR__)
Code.require_file("../support/resilient_agent.ex", __DIR__)

defmodule Jido.Examples.ModelResilience.RepairAndBudgetsTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.ModelResilience.{ResilientAgent, ScriptedInferenceClient}

  test "a truncated answer starts one output-repair attempt" do
    result = ask(%{input: "Complete the answer", model: "offline:truncated"})

    assert result.status == :completed
    assert result.output == "Complete repaired answer"
    assert result.model_calls == 2
    assert result.retries == 1
    assert Enum.map(result.model_attempts, & &1.outcome.finish_reason) == [:length, :stop]
  end

  test "an output-size failure is repaired within the request limit" do
    result =
      ask(%{
        input: "Keep it short",
        model: "offline:long-output",
        limits: %{output_chars: 10}
      })

    assert result.status == :completed
    assert result.output == "Short"
    assert result.retries == 1
    assert result.model_calls == 2
  end

  test "a token budget rejects the next model attempt" do
    result =
      ask(%{
        input: "Complete the answer",
        model: "offline:truncated",
        limits: %{total_tokens: 10}
      })

    assert result.status == :blocked
    assert result.reason_code == :limits
    assert result.model_calls == 1
    assert result.usage.total_tokens == 12
  end

  defp ask(data) do
    agent = ResilientAgent.instantiate!(id: "repair-#{System.unique_integer([:positive])}")

    assert {:ok, _candidate, [%Jido.Agent.Directive.Reply{signal: reply}]} =
             ResilientAgent.cmd(agent, ResilientAgent.request_signal!(data),
               context: %{jido_ai_inference_client: ScriptedInferenceClient}
             )

    reply.data
  end
end
