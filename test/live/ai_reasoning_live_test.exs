defmodule JidoTest.AI.ReasoningLiveTest do
  use ExUnit.Case, async: false

  alias Jido.AITest.ChainOfThoughtAgent
  alias Jido.Agent.Directive.Reply
  alias Jido.AgentServer
  alias JidoTest.AI.LiveTrace

  @moduletag :live
  @test_key "JIDO_LIVE_OPENAI_API_KEY"

  setup_all do
    test_key = System.get_env(@test_key)

    unless present?(test_key) do
      flunk("#{@test_key} is required when mix test.live selects the AI provider test")
    end

    previous_key = System.get_env("OPENAI_API_KEY")
    System.put_env("OPENAI_API_KEY", test_key)

    on_exit(fn -> restore_env("OPENAI_API_KEY", previous_key) end)

    {:ok, test_key: test_key}
  end

  test "a provider result has usage, correlated telemetry, and a redacted trace", %{
    test_key: test_key
  } do
    owner = self()
    handler_id = "jido-ai-live-#{System.unique_integer([:positive])}"

    assert :ok =
             :telemetry.attach_many(
               handler_id,
               Jido.Telemetry.AI.owned_events() ++ ReqLLM.Telemetry.stable_events(),
               fn event, measurements, metadata, _config ->
                 send(owner, {:telemetry, event, measurements, metadata})
               end,
               nil
             )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    instance = String.to_atom("jido_ai_live_#{System.unique_integer([:positive])}")
    start_supervised!({Jido, name: instance, namespace: Atom.to_string(instance)}, id: instance)

    assert {:ok, server} = Jido.start_agent(instance, ChainOfThoughtAgent, id: "ai-live-agent")
    assert :ok = AgentServer.await_ready(server)

    prompt =
      "Use at least three numbered steps. A shop has 12 boxes with 8 markers in each box. " <>
        "It gives away 17 markers. How many markers remain?"

    assert {:ok, _agent, [%Reply{signal: reply}]} =
             AgentServer.call(
               server,
               ChainOfThoughtAgent.request_signal!(%{input: prompt}),
               60_000
             )

    events = receive_events([])

    assert reply.data.status == :completed
    assert reply.data.model_calls == 1
    assert reply.data.output =~ "79"
    assert reply.data.reasoning.method == :chain_of_thought
    assert reply.data.reasoning.steps_count >= 3
    assert reply.data.reasoning.conclusion =~ "79"
    assert reply.data.usage.input_tokens > 0
    assert reply.data.usage.output_tokens > 0

    assert [attempt] = reply.data.model_attempts

    after_context = Jido.AI.Context.Snapshot.decode!(attempt.context.after)
    assert after_context["stage"] == "completed"
    assert after_context["response"]["call_metadata"]["usage"]["input_tokens"] > 0
    assert after_context["response"]["call_metadata"]["usage"]["output_tokens"] > 0

    assert {_, reasoning_measurements, reasoning_stop} =
             find_event(events, [:jido, :ai, :reasoning, :stop])

    assert {_, _, request_stop} = find_event(events, [:req_llm, :request, :stop])
    assert {_, agent_measurements, agent_stop} = find_event(events, [:jido, :ai, :agent, :stop])

    assert reasoning_stop.reasoning_method == :chain_of_thought
    assert reasoning_stop.status == :ok
    assert reasoning_measurements.duration > 0
    assert attempt.req_llm_request_id == request_stop.request_id
    assert agent_stop.status == :completed
    assert agent_measurements.model_calls == 1
    assert agent_measurements.reasoning_steps == reply.data.reasoning.steps_count

    trace_path =
      LiveTrace.write!("tmp/live/ai_reasoning.json", events, %{
        status: reply.data.status,
        model_calls: reply.data.model_calls,
        reasoning_steps: reply.data.reasoning.steps_count,
        retries: reply.data.retries,
        usage: reply.data.usage
      })

    trace_text = File.read!(trace_path)
    refute trace_text =~ prompt
    refute trace_text =~ "12 boxes"
    refute trace_text =~ "markers remain"
    refute trace_text =~ test_key
  end

  defp receive_events(events) do
    receive do
      {:telemetry, event, measurements, metadata} ->
        receive_events([{event, measurements, metadata} | events])
    after
      200 -> Enum.reverse(events)
    end
  end

  defp find_event(events, name), do: Enum.find(events, &(elem(&1, 0) == name))

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
