defmodule Jido.AI.OpenTelemetryTest do
  use Covenant.Case, component: "jido_ai.observability", async: false

  @moduletag obligation: [
               "jido_ai.observability.I1",
               "jido_ai.observability.I2",
               "jido_ai.observability.I3",
               "jido_ai.observability.I4",
               "jido_ai.observability.I5"
             ]

  import Mimic

  alias Jido.AI.Telemetry
  alias Jido.AI.Telemetry.CorrelationStore
  alias Jido.AITest.OpenTelemetryTracer, as: TestTracer

  defmodule TracedTool do
    use Jido.Action,
      id: "jido.ai/test/traced-tool",
      name: "traced_tool",
      description: "Runs one traced tool operation.",
      schema: Zoi.object(%{value: Zoi.integer()}),
      output_schema: Zoi.object(%{value: Zoi.integer()})

    @impl Jido.Action
    def run(%{value: value}, _context) do
      tracer = :opentelemetry.get_application_tracer(__MODULE__)
      span = :otel_tracer.start_span(tracer, "tool.child", %{kind: :internal})
      :otel_span.end_span(span)
      {:ok, %{value: value}}
    end
  end

  defmodule TracedAgent do
    use Jido.AI.Agent,
      name: "traced_agent",
      description: "Tests portable GenAI telemetry",
      id: "jido.ai/test/traced-agent",
      vsn: 7

    ai do
      reasoning Jido.AI.Reasoning.ReAct

      tools do
        action Jido.AI.OpenTelemetryTest.TracedTool
      end
    end
  end

  setup :set_mimic_global
  setup :verify_on_exit!

  setup do
    previous_tracer = :opentelemetry.get_tracer()
    previous_ai_config = Application.fetch_env(:jido, :ai_opentelemetry)
    previous_jido_config = Application.fetch_env(:jido, :opentelemetry)
    previous_context = :otel_ctx.attach(:otel_ctx.new())

    assert :opentelemetry.set_default_tracer({TestTracer, self()})
    Application.delete_env(:jido, :ai_opentelemetry)
    Application.put_env(:jido, :opentelemetry, %{enabled: false})
    :telemetry.detach("jido-ai-open-telemetry")
    ReqLLM.OpenTelemetry.detach("jido-ai-req-llm-open-telemetry")
    :ok = Telemetry.attach_open_telemetry()

    on_exit(fn ->
      :telemetry.detach("jido-ai-open-telemetry")
      :telemetry.detach("jido-ai-req-llm-open-telemetry")
      :otel_ctx.detach(previous_context)
      :opentelemetry.set_default_tracer(previous_tracer)
      restore_config(:jido, :ai_opentelemetry, previous_ai_config)
      restore_config(:jido, :opentelemetry, previous_jido_config)
    end)

    :ok
  end

  test "standard GenAI spans keep stable identity, conversation context, and tool parentage" do
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    expect(ReqLLM, :generate_text, 2, fn model, context, options ->
      record_model_probe(options)

      case Agent.get_and_update(calls, fn count -> {count + 1, count + 1} end) do
        1 ->
          tool_calls = [ReqLLM.ToolCall.new("tool-call-1", "traced_tool", ~s({"value":7}))]
          {:ok, tool_response(model, context, tool_calls, "tool-request")}

        2 ->
          {:ok, response(model, context, "Done.", "final")}
      end
    end)

    instance = String.to_atom("jido_ai_otel_#{System.unique_integer([:positive])}")
    start_supervised!({Jido, name: instance, namespace: Atom.to_string(instance)}, id: instance)

    assert {:ok, server} = Jido.start_agent(instance, TracedAgent, id: "runtime-agent-1")
    assert :ok = Jido.AgentServer.await_ready(server)

    assert {:ok, _agent, _directives} =
             Jido.AgentServer.call(server, TracedAgent.request_signal!(%{input: "Run the tool."}))

    events = receive_otel([])

    {agent_span, _agent_parent, agent_start} = find_start(events, "invoke_agent traced_agent")
    agent_ids = TestTracer.ids(agent_span)

    assert agent_start.attributes["gen_ai.operation.name"] == "invoke_agent"
    assert agent_start.attributes["gen_ai.agent.id"] == "jido.ai/test/traced-agent"
    assert agent_start.attributes["gen_ai.agent.name"] == "traced_agent"
    assert agent_start.attributes["gen_ai.agent.version"] == "7"

    assert agent_start.attributes["gen_ai.agent.description"] ==
             "Tests portable GenAI telemetry"

    assert agent_start.attributes["jido.ai.agent.instance.id"] == "runtime-agent-1"

    {tool_span, tool_parent, tool_start} = find_start(events, "execute_tool traced_tool")
    tool_ids = TestTracer.ids(tool_span)

    assert TestTracer.ids(tool_parent).span_id == agent_ids.span_id
    assert tool_start.attributes["gen_ai.operation.name"] == "execute_tool"
    assert tool_start.attributes["gen_ai.tool.call.id"] == "tool-call-1"
    assert tool_start.attributes["gen_ai.tool.name"] == "traced_tool"
    assert tool_start.attributes["gen_ai.tool.type"] == "function"

    assert tool_start.attributes["gen_ai.tool.description"] ==
             "Runs one traced tool operation."

    assert tool_start.attributes["gen_ai.conversation.id"] ==
             "session:runtime-agent-1:thread"

    assert tool_start.attributes["session.id"] == "session:runtime-agent-1"

    {_child_span, child_parent, _child_start} = find_start(events, "tool.child")
    assert TestTracer.ids(child_parent).span_id == tool_ids.span_id

    agent_finish = merged_attributes(events, agent_ids)
    assert agent_finish["gen_ai.conversation.id"] == "session:runtime-agent-1:thread"
    assert agent_finish["session.id"] == "session:runtime-agent-1"
    assert agent_finish["jido.ai.session.id"] == "session:runtime-agent-1"
    assert agent_finish["jido.ai.run.id"]

    model_starts = find_starts_with(events, "chat ")

    assert length(model_starts) == 2,
           "expected two model spans, got #{inspect(start_names(events))}"

    assert Enum.all?(model_starts, fn {_span, parent, opts} ->
             TestTracer.ids(parent).span_id == agent_ids.span_id and
               opts.attributes["gen_ai.conversation.id"] ==
                 "session:runtime-agent-1:thread"
           end)

    refute vendor_attribute?(agent_start.attributes)
    refute vendor_attribute?(tool_start.attributes)
  end

  test "failed owned spans emit error type, status message, and restore context" do
    before = :otel_tracer.current_span_ctx()
    attempt_id = "failed-tool-#{System.unique_integer([:positive])}"

    start_metadata = %{
      attempt_id: attempt_id,
      tool_name: "failed_tool",
      tool_call_id: "call-failed",
      turn_id: "turn-failed"
    }

    :telemetry.execute(
      [:jido, :ai, :tool, :start],
      %{monotonic_time: System.monotonic_time()},
      start_metadata
    )

    active = :otel_tracer.current_span_ctx()
    refute active == before

    :telemetry.execute(
      [:jido, :ai, :tool, :stop],
      %{duration: 10},
      Map.merge(start_metadata, %{
        status: :error,
        error_type: :tool_execution_failed,
        retryable?: false
      })
    )

    assert :otel_tracer.current_span_ctx() == before

    events = receive_otel([])
    {span, _parent, _opts} = find_start(events, "execute_tool failed_tool")
    ids = TestTracer.ids(span)
    final = merged_attributes(events, ids)

    assert final["error.type"] == "tool_execution_failed"
    assert final["jido.ai.tool.retryable"] == false
    assert {:otel_status, ids, :error, "tool_execution_failed"} in events
  end

  test "expired span correlations close the span and restore a local context" do
    before = :otel_tracer.current_span_ctx()
    attempt_id = "expired-tool-#{System.unique_integer([:positive])}"

    :telemetry.execute(
      [:jido, :ai, :tool, :start],
      %{monotonic_time: System.monotonic_time()},
      %{attempt_id: attempt_id, tool_name: "expired_tool", turn_id: "turn-expired"}
    )

    refute :otel_tracer.current_span_ctx() == before
    assert CorrelationStore.prune_stale(0) >= 1
    assert :otel_tracer.current_span_ctx() == before

    events = receive_otel([])
    {span, _parent, _opts} = find_start(events, "execute_tool expired_tool")
    ids = TestTracer.ids(span)
    final = merged_attributes(events, ids)

    assert final["error.type"] == "jido.ai.telemetry.correlation_expired"

    assert {:otel_status, ids, :error, "jido.ai.telemetry.correlation_expired"} in events
    assert Enum.any?(events, &match?({:otel_end, ^ids, _timestamp}, &1))
  end

  defp receive_otel(events) do
    receive do
      {:otel_start, _span, _parent, _name, _opts} = event -> receive_otel([event | events])
      {:otel_set_attribute, _ids, _key, _value} = event -> receive_otel([event | events])
      {:otel_set_attributes, _ids, _attributes} = event -> receive_otel([event | events])
      {:otel_event, _ids, _name, _attributes} = event -> receive_otel([event | events])
      {:otel_events, _ids, _span_events} = event -> receive_otel([event | events])
      {:otel_status, _ids, _code, _description} = event -> receive_otel([event | events])
      {:otel_update_name, _ids, _name} = event -> receive_otel([event | events])
      {:otel_end, _ids, _timestamp} = event -> receive_otel([event | events])
    after
      20 -> Enum.reverse(events)
    end
  end

  defp find_start(events, name) do
    case find_starts(events, name) do
      [{span, parent, opts} | _rest] -> {span, parent, opts}
      [] -> flunk("missing OpenTelemetry span #{inspect(name)}")
    end
  end

  defp find_starts(events, name) do
    for {:otel_start, span, parent, ^name, opts} <- events, do: {span, parent, opts}
  end

  defp find_starts_with(events, prefix) do
    for {:otel_start, span, parent, name, opts} <- events,
        String.starts_with?(name, prefix),
        do: {span, parent, opts}
  end

  defp start_names(events) do
    for {:otel_start, _span, _parent, name, _opts} <- events, do: name
  end

  defp merged_attributes(events, ids) do
    Enum.reduce(events, %{}, fn
      {:otel_set_attributes, event_ids, attributes}, merged when event_ids == ids ->
        Map.merge(merged, attributes)

      _event, merged ->
        merged
    end)
  end

  defp vendor_attribute?(attributes) do
    Enum.any?(Map.keys(attributes), fn key ->
      String.starts_with?(key, "langfuse.") or String.starts_with?(key, "dd.")
    end)
  end

  defp record_model_probe(options) do
    conversation_id = get_in(options, [:telemetry, :conversation_id])
    tracer = :opentelemetry.get_application_tracer(__MODULE__)

    span =
      :otel_tracer.start_span(tracer, "chat mock", %{
        kind: :client,
        attributes: %{
          "gen_ai.operation.name" => "chat",
          "gen_ai.request.model" => "mock",
          "gen_ai.conversation.id" => conversation_id
        }
      })

    :otel_span.end_span(span)
  end

  defp restore_config(application, key, {:ok, config}),
    do: Application.put_env(application, key, config)

  defp restore_config(application, key, :error),
    do: Application.delete_env(application, key)

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
