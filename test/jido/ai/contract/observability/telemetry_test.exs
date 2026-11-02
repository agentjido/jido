defmodule Jido.AI.TelemetryTest do
  use Covenant.Case, component: "jido_ai.observability", async: false

  @moduletag obligation: [
               "jido_ai.observability.I1",
               "jido_ai.observability.I2",
               "jido_ai.observability.I4",
               "jido_ai.observability.I5"
             ]

  import ExUnit.CaptureLog
  import Mimic

  alias Jido.AI.Telemetry
  alias Jido.AITest.SimpleAgent
  alias Jido.AgentServer

  setup :set_mimic_global
  setup :verify_on_exit!

  test "the facade exposes native, lower-layer, and ReqLLM events" do
    events = Telemetry.events()

    assert [:jido, :ai, :agent, :start] in events
    assert [:jido, :ai, :reasoning, :stop] in events
    assert [:jido, :ai, :tool, :stop] in events
    assert [:jido, :ai, :telemetry, :correlation, :cleanup] in events
    assert [:jido, :agent_server, :turn, :stop] in events
    assert [:jido, :action, :stop] in events
    assert [:runic, :runner, :runnable, :stop] in events
    assert [:req_llm, :request, :stop] in events
    assert [:req_llm, :token_usage] in events

    names = Enum.map(Telemetry.metrics(), & &1.name)
    assert [:jido, :ai, :agent, :stop, :duration] in names
    assert [:jido, :ai, :reasoning, :stop, :duration] in names
    assert [:jido, :ai, :model, :input_tokens] in names
    assert [:jido, :ai, :model, :cache_read_tokens] in names
    assert [:jido, :ai, :telemetry, :correlation, :expired] in names
    assert [:jido, :ai, :telemetry, :correlation, :size] in names
  end

  test "one AgentServer request correlates Agent, model, and tool telemetry" do
    owner = self()
    handler_id = "jido-ai-test-#{System.unique_integer([:positive])}"

    assert :ok =
             :telemetry.attach_many(
               handler_id,
               Telemetry.owned_events() ++ ReqLLM.Telemetry.stable_events(),
               fn event, measurements, metadata, _config ->
                 send(owner, {:telemetry, event, measurements, metadata})
               end,
               nil
             )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {:ok, calls} = Agent.start_link(fn -> 0 end)

    expect(ReqLLM, :generate_text, 2, fn model, context, options ->
      assert get_in(options, [:telemetry, :conversation_id]) ==
               "session:telemetry-agent:thread"

      case Agent.get_and_update(calls, fn count -> {count + 1, count + 1} end) do
        1 ->
          tool_calls = [ReqLLM.ToolCall.new("sum-1", "add", ~s({"left":2,"right":3}))]
          {:ok, tool_response(model, context, tool_calls, "tool-request")}

        2 ->
          {:ok, response(model, context, "The result is 5.", "final")}
      end
    end)

    instance = String.to_atom("jido_ai_telemetry_#{System.unique_integer([:positive])}")
    start_supervised!({Jido, name: instance, namespace: Atom.to_string(instance)}, id: instance)

    assert {:ok, server} = Jido.start_agent(instance, SimpleAgent, id: "telemetry-agent")
    assert :ok = AgentServer.await_ready(server)

    assert {:ok, _agent, _directives} =
             AgentServer.call(
               server,
               SimpleAgent.request_signal!(%{input: "Add 2 and 3."})
             )

    events = receive_events([])

    assert {_, _, agent_start} = find_event(events, [:jido, :ai, :agent, :start])
    assert agent_start.agent_module == SimpleAgent
    assert agent_start.agent_definition_id == "jido.ai/agents/simple"
    assert agent_start.agent_description == "Answer one request with guardrails and multiple tools"
    assert agent_start.agent_version == "3"
    assert agent_start.reasoning == Jido.AI.Reasoning.ReAct
    assert agent_start.request_id
    assert agent_start.turn_id

    assert {_, tool_measurements, tool_stop} =
             find_event(events, [:jido, :ai, :tool, :stop])

    assert tool_stop.tool_name == "add"
    assert tool_stop.tool_call_id == "sum-1"
    assert tool_stop.tool_description == "Add two numbers."
    assert tool_stop.run_id
    assert tool_stop.session_id == "session:telemetry-agent"
    assert tool_stop.thread_id == "session:telemetry-agent:thread"
    assert tool_stop.turn_id == agent_start.turn_id
    assert tool_stop.status == :ok
    assert is_integer(tool_measurements.duration)

    assert {_, agent_measurements, agent_stop} =
             find_event(events, [:jido, :ai, :agent, :stop])

    assert agent_stop.status == :completed
    assert agent_stop.thread_id == "session:telemetry-agent:thread"
    assert agent_measurements.model_calls == 2
    assert agent_measurements.tool_calls == 1
  end

  test "semantic logging is derived from telemetry and excludes content" do
    restore_telemetry_config_on_exit()

    Application.put_env(:jido, :ai_telemetry, semantic_log_mode: :errors)

    log =
      capture_log(fn ->
        :telemetry.execute(
          [:jido, :ai, :agent, :stop],
          %{duration: 10},
          %{
            agent_name: "safe_agent",
            status: :failed,
            error_type: :provider_error,
            prompt: "must-not-be-logged",
            output: "must-not-be-logged"
          }
        )
      end)

    assert log =~ "[jido.ai.semantic]"
    assert log =~ "status=failed"
    assert log =~ "error_type=provider_error"
    refute log =~ "must-not-be-logged"
  end

  test "reasoning errors carry a low-cardinality error type" do
    owner = self()
    handler_id = "jido-ai-reasoning-error-#{System.unique_integer([:positive])}"

    assert :ok =
             :telemetry.attach(
               handler_id,
               [:jido, :ai, :reasoning, :stop],
               fn event, measurements, metadata, _config ->
                 send(owner, {:telemetry, event, measurements, metadata})
               end,
               nil
             )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:error, :invalid_reasoning} =
             Telemetry.with_reasoning(%{}, %{method: :test}, fn ->
               {:error, :invalid_reasoning}
             end)

    assert_receive {:telemetry, [:jido, :ai, :reasoning, :stop], _measurements, metadata}
    assert metadata.status == :error
    assert metadata.error_type == :invalid_reasoning
  end

  test "semantic log modes follow the core Jido policy" do
    restore_telemetry_config_on_exit()

    Application.put_env(:jido, :ai_telemetry, semantic_log_mode: :off)

    assert capture_log(fn -> emit_agent_stop(:failed) end) == ""

    Application.put_env(:jido, :ai_telemetry, semantic_log_mode: :errors)

    assert capture_log(fn -> emit_agent_stop(:completed) end) == ""
    assert capture_log(fn -> emit_agent_stop(:failed) end) =~ "status=failed"

    Application.put_env(:jido, :ai_telemetry, semantic_log_mode: :interesting)

    assert capture_log([level: :debug], fn -> emit_agent_stop(:blocked) end) =~
             "status=blocked"

    Application.put_env(:jido, :ai_telemetry, semantic_log_mode: :all)

    assert capture_log([level: :debug], fn ->
             :telemetry.execute(
               [:jido, :ai, :agent, :start],
               %{system_time: System.system_time()},
               %{agent_name: "mode_agent"}
             )
           end) =~ "event=ai.agent.start"

    assert capture_log([level: :debug], fn ->
             :telemetry.execute([:req_llm, :token_usage], %{input_tokens: 10}, %{})
           end) == ""
  end

  defp receive_events(events) do
    receive do
      {:telemetry, event, measurements, metadata} ->
        receive_events([{event, measurements, metadata} | events])
    after
      20 -> Enum.reverse(events)
    end
  end

  defp find_event(events, name), do: Enum.find(events, &(elem(&1, 0) == name))

  defp emit_agent_stop(status) do
    :telemetry.execute(
      [:jido, :ai, :agent, :stop],
      %{duration: 10},
      %{agent_name: "mode_agent", status: status}
    )
  end

  defp restore_telemetry_config_on_exit do
    previous = Application.fetch_env(:jido, :ai_telemetry)

    on_exit(fn ->
      case previous do
        {:ok, config} -> Application.put_env(:jido, :ai_telemetry, config)
        :error -> Application.delete_env(:jido, :ai_telemetry)
      end
    end)
  end

  defp response(model, context, text, id) do
    %ReqLLM.Response{
      id: id,
      model: model,
      context: context,
      finish_reason: :stop,
      message: ReqLLM.Context.assistant(text)
    }
  end

  defp tool_response(model, context, calls, id) do
    %ReqLLM.Response{
      id: id,
      model: model,
      context: context,
      finish_reason: :tool_calls,
      message: ReqLLM.Context.assistant("", tool_calls: calls)
    }
  end
end
