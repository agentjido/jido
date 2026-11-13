Code.require_file("../support/scripted_inference_client.ex", __DIR__)
Code.require_file("../support/resilient_agent.ex", __DIR__)

defmodule Jido.Examples.ModelResilience.RetryAndFallbackTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.ModelResilience.{ResilientAgent, ScriptedInferenceClient}

  test "a retryable primary failure can use an ordered fallback" do
    assert %{status: :completed} =
             result =
             ask(%{
               input: "Use a fallback",
               model: "offline:primary-outage",
               fallback_models: ["offline:fallback"],
               limits: %{retries: 0}
             })

    assert result.output == "Offline answer from offline:fallback"
    assert result.model_calls == 2
    assert result.retries == 1
    assert Enum.map(result.model_attempts, & &1.model) == ["offline:primary-outage", "offline:fallback"]
    assert List.last(result.model_attempts).outcome.usage.total_cost == 0.001
    refute JSON.encode!(result.model_attempts) =~ "must-not-be-recorded"
  end

  test "an authorization failure does not retry or use a fallback" do
    result =
      ask(%{
        input: "Do not hide authorization failure",
        model: "offline:invalid-credentials",
        fallback_models: ["offline:fallback"]
      })

    assert result.status == :failed
    assert result.model_calls == 1
    assert result.retries == 0

    assert [%{model: "offline:invalid-credentials", outcome: %{retryable: false}}] =
             result.model_attempts
  end

  test "a model-call budget stops before fallback" do
    result =
      ask(%{
        input: "Use a fallback",
        model: "offline:primary-outage",
        fallback_models: ["offline:fallback"],
        limits: %{model_calls: 1, retries: 0}
      })

    assert result.status == :blocked
    assert result.reason_code == :limits
    assert result.model_calls == 1
    assert length(result.model_attempts) == 1
  end

  defp ask(data) do
    agent = ResilientAgent.instantiate!(id: "resilience-#{System.unique_integer([:positive])}")
    signal = ResilientAgent.request_signal!(data)

    assert {:ok, _candidate, [%Jido.Agent.Directive.Reply{signal: reply}]} =
             ResilientAgent.cmd(agent, signal, context: %{jido_ai_inference_client: ScriptedInferenceClient})

    reply.data
  end
end
