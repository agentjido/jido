Code.require_file("../support/scripted_inference_client.ex", __DIR__)
Code.require_file("../support/resilient_agent.ex", __DIR__)

defmodule Jido.Examples.ModelResilience.FailureMatrixTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.Examples.ModelResilience.{ResilientAgent, ScriptedInferenceClient}

  test "a tool error becomes safe model input and the request can complete" do
    {result, candidate} = ask(%{input: "Check inventory", model: "offline:tool-error"})

    assert result.status == :completed
    assert result.output == "The inventory tool is unavailable."
    assert result.tool_calls == 1
    assert result.tool_errors == 1
    assert result.tool_rounds == 1

    tool_message =
      candidate.state.session.thread.entries
      |> Enum.find(&(&1.kind == :ai_message and &1.payload["role"] == "tool"))

    assert get_in(tool_message.payload, ["output", "status"]) == "error"
    assert get_in(tool_message.payload, ["output", "error", "retryable"]) == true
  end

  test "the offline matrix gives a stable outcome for each provider condition" do
    cases = [
      {"offline:ok", :completed, 1},
      {"offline:invalid-credentials", :failed, 1},
      {"offline:primary-outage", :failed, 2},
      {"offline:truncated", :completed, 2},
      {"offline:long-output", :completed, 1}
    ]

    assert Enum.map(cases, fn {model, expected_status, expected_calls} ->
             {result, _candidate} = ask(%{input: "matrix case", model: model})
             {model, result.status, result.model_calls, expected_status, expected_calls}
           end) ==
             Enum.map(cases, fn {model, status, calls} -> {model, status, calls, status, calls} end)
  end

  test "a partial stream fails without committing an assistant message" do
    agent = ResilientAgent.instantiate!(id: "partial-stream-agent")
    request = ResilientAgent.request_signal!(%{input: "Stream this", model: "offline:partial-stream", stream: true})

    assert {:ok, candidate, [%Jido.Agent.Directive.Reply{signal: reply}]} =
             ResilientAgent.cmd(agent, request,
               context: %{
                 jido_ai_inference_client: ScriptedInferenceClient,
                 jido_ai_dispatch: {:pid, target: self()}
               }
             )

    assert reply.data.status == :failed
    assert reply.data.model_calls == 1

    signals = receive_stream_signals([])

    assert Enum.map(signals, & &1.type) == [
             "jido.ai.model.stream.started",
             "jido.ai.model.stream.chunk",
             "jido.ai.model.stream.failed"
           ]

    refute Enum.any?(candidate.state.session.thread.entries, fn entry ->
             entry.kind == :ai_message and entry.payload["role"] == "assistant"
           end)
  end

  test "hosted Agent telemetry reports the final failed status without content" do
    handler = {__MODULE__, make_ref()}
    owner = self()

    :ok =
      :telemetry.attach(
        handler,
        [:jido, :ai, :agent, :stop],
        fn event, measurements, metadata, _config ->
          send(owner, {:agent_event, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    suffix = System.unique_integer([:positive])
    instance = :"resilience_telemetry_#{suffix}"
    start_supervised!({Jido, name: instance}, id: instance)

    assert {:ok, server} =
             Jido.start_agent(instance, ResilientAgent, id: "resilience-telemetry-agent")

    assert :ok = Jido.AgentServer.await_ready(server)

    signal =
      ResilientAgent.request_signal!(%{
        input: "private prompt",
        model: "offline:invalid-credentials"
      })

    assert {:ok, %Jido.AgentServer.TurnResult{reply: reply}} =
             Jido.AgentServer.call(server, signal, context: %{jido_ai_inference_client: ScriptedInferenceClient})

    assert reply.data.status == :failed

    assert_receive {:agent_event, [:jido, :ai, :agent, :stop], measurements, metadata},
                   1_000

    assert metadata.status == :failed
    assert is_integer(measurements.duration)
    assert measurements.model_calls == 1
    refute Map.has_key?(metadata, :input)
    refute Map.has_key?(metadata, :output)
  end

  defp ask(data) do
    agent = ResilientAgent.instantiate!(id: "matrix-#{System.unique_integer([:positive])}")

    assert {:ok, candidate, [%Jido.Agent.Directive.Reply{signal: reply}]} =
             ResilientAgent.cmd(agent, ResilientAgent.request_signal!(data),
               context: %{jido_ai_inference_client: ScriptedInferenceClient}
             )

    {reply.data, candidate}
  end

  defp receive_stream_signals(signals) do
    receive do
      {:signal, signal}
      when signal.type in [
             "jido.ai.model.stream.started",
             "jido.ai.model.stream.chunk",
             "jido.ai.model.stream.failed"
           ] ->
        receive_stream_signals(signals ++ [signal])
    after
      20 -> signals
    end
  end
end
