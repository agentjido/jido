defmodule Jido.AI.Contract.ObservabilityBoundariesTest do
  use Covenant.Case, component: "jido_ai.observability", async: false

  import ExUnit.CaptureLog

  alias Jido.Telemetry.AI, as: Telemetry
  alias Jido.Telemetry.AI.{CorrelationStore, OpenTelemetry}
  alias Jido.AITest.OpenTelemetryTracer, as: TestTracer
  alias Jido.AITest.{SimpleAgent, Tools}

  defmodule CleanupProbe do
    def throw(_key, _value), do: throw(:cleanup_failed)
  end

  @tag obligation: ["jido_ai.observability.I1", "jido_ai.observability.I2"]
  test "runtime bridges retain request, tool, and terminal correlation" do
    owner = self()
    handler_id = "contract-runtime-#{System.unique_integer([:positive])}"

    handler = fn event, measurements, metadata, target ->
      send(target, {:contract_telemetry, event, measurements, metadata})
    end

    assert :ok = Telemetry.attach(handler_id, handler, owner)
    assert {:error, :already_exists} = Telemetry.attach(handler_id, handler, owner)
    on_exit(fn -> :telemetry.detach(handler_id) end)

    turn_id = "contract-turn-#{System.unique_integer([:positive])}"

    start_metadata = %{
      signal_type: "jido.ai.request",
      signal_id: "request-1",
      turn_id: turn_id,
      agent_id: "agent-1",
      agent_module: SimpleAgent
    }

    assert :ok =
             Telemetry.handle_runtime_event(
               [:jido, :agent_server, :turn, :start],
               %{system_time: 1},
               start_metadata,
               nil
             )

    assert :ok =
             Telemetry.record_agent_context(%{turn_id: turn_id}, %{
               request_id: "request-1",
               run_id: "run-1",
               session_id: "session-1",
               thread_id: "thread-1",
               ignored: "value"
             })

    assert :ok = Telemetry.record_agent_context(%{}, %{})

    assert :ok =
             Telemetry.record_tool_calls(%{turn_id: turn_id}, %{
               "tool_0" => %{
                 id: "call-1",
                 name: "add",
                 description: "Add two numbers.",
                 action: Tools.Add
               },
               "invalid" => :ignored
             })

    assert :ok = Telemetry.record_tool_calls(%{}, %{})

    action_metadata = %{
      turn_id: turn_id,
      component: "tools",
      component_kind: :parallel,
      node_path: ["tool_0"],
      action: Tools.Add,
      action_name: "wrong_name",
      attempt_id: "attempt-1"
    }

    assert :ok =
             Telemetry.handle_runtime_event(
               [:jido, :action, :start],
               %{system_time: 2},
               action_metadata,
               nil
             )

    assert :ok =
             Telemetry.handle_runtime_event(
               [:jido, :action, :stop],
               %{duration: 3},
               Map.put(action_metadata, :outcome, :ok),
               nil
             )

    assert :ok =
             Telemetry.handle_runtime_event(
               [:jido, :action, :exception],
               %{duration: 4},
               Map.put(action_metadata, :error_type, :tool_failed),
               nil
             )

    assert :ok =
             Telemetry.handle_runtime_event(
               [:req_llm, :request, :start],
               %{},
               %{request_id: "model-request-1", request_options: %{"conversation_id" => "thread-1"}},
               nil
             )

    assert Telemetry.take_model_request_id("thread-1") == "model-request-1"
    assert Telemetry.take_model_request_id(:invalid) == nil

    assert :ok =
             Telemetry.record_agent_summary(%{turn_id: turn_id}, %{
               status: :completed,
               run_id: "run-1",
               session_id: "session-1",
               thread_id: "thread-1",
               model_calls: 2,
               tool_calls: 1,
               usage: %{"tokens" => %{"input_tokens" => 5}, "total_cost" => 0.1}
             })

    assert :ok = Telemetry.record_agent_summary(%{}, %{})

    assert :ok =
             Telemetry.handle_runtime_event(
               [:jido, :agent_server, :turn, :stop],
               %{duration: 5},
               Map.merge(start_metadata, %{status: :completed, committed?: true}),
               nil
             )

    assert :ok = Telemetry.handle_runtime_event([:unrelated], %{}, %{}, nil)

    events = receive_telemetry([])
    assert {_, _, agent_start} = find_event(events, [:jido, :ai, :agent, :start])
    assert agent_start.agent_description == "Answer one request with guardrails and multiple tools"
    assert agent_start.reasoning == Jido.AI.Reasoning.ReAct

    tool_events =
      Enum.filter(events, fn {event, _measurements, _metadata} ->
        Enum.take(event, 3) == [:jido, :ai, :tool]
      end)

    assert Enum.any?(tool_events, fn {event, _measurements, metadata} ->
             event == [:jido, :ai, :tool, :stop] and metadata.tool_name == "add" and
               metadata.tool_call_id == "call-1" and metadata.status == :ok
           end)

    assert {_, measurements, terminal} = find_event(events, [:jido, :ai, :agent, :stop])
    assert terminal.run_id == "run-1"
    assert terminal.status == :completed
    assert measurements.model_calls == 2
    assert measurements.input_tokens == 5
  end

  @tag obligation: ["jido_ai.observability.I1", "jido_ai.observability.I5"]
  test "reasoning and semantic boundaries keep errors low-cardinality and content safe" do
    owner = self()
    handler_id = "contract-reasoning-#{System.unique_integer([:positive])}"

    assert :ok =
             :telemetry.attach_many(
               handler_id,
               [
                 [:jido, :ai, :reasoning, :start],
                 [:jido, :ai, :reasoning, :stop],
                 [:jido, :ai, :reasoning, :exception]
               ],
               fn event, measurements, metadata, target ->
                 send(target, {:contract_telemetry, event, measurements, metadata})
               end,
               owner
             )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    turn_id = "reasoning-turn-#{System.unique_integer([:positive])}"

    CorrelationStore.put({:agent, turn_id}, %{
      agent_name: "contract_agent",
      turn_id: turn_id,
      thread_id: "reasoning-thread"
    })

    assert {:ok, :done} =
             Telemetry.with_reasoning(%{turn_id: turn_id}, %{method: :contract}, fn -> {:ok, :done} end)

    assert :plain =
             Telemetry.with_reasoning(%{turn_id: turn_id}, %{method: :contract}, fn -> :plain end)

    assert {:error, {:provider, :down}} =
             Telemetry.with_reasoning(%{turn_id: turn_id}, %{method: :contract}, fn ->
               {:error, {:provider, :down}}
             end)

    assert catch_throw(
             Telemetry.with_reasoning(%{turn_id: turn_id}, %{method: :contract}, fn ->
               throw(:reasoning_failed)
             end)
           ) == :reasoning_failed

    events = receive_telemetry([])

    assert Enum.any?(events, fn {event, _measurements, metadata} ->
             event == [:jido, :ai, :reasoning, :stop] and metadata.status == :unknown
           end)

    assert Enum.any?(events, fn {event, _measurements, metadata} ->
             event == [:jido, :ai, :reasoning, :stop] and Map.get(metadata, :error_type) == :provider
           end)

    assert Enum.any?(events, fn {event, _measurements, metadata} ->
             event == [:jido, :ai, :reasoning, :exception] and metadata.error_type == :throw
           end)

    previous = Application.fetch_env(:jido, :ai_telemetry)

    on_exit(fn ->
      case previous do
        {:ok, config} -> Application.put_env(:jido, :ai_telemetry, config)
        :error -> Application.delete_env(:jido, :ai_telemetry)
      end
    end)

    Application.put_env(:jido, :ai_telemetry, %{
      semantic_log_mode: :interesting,
      semantic_slow_threshold_ms: 0
    })

    unsafe = "line\\one\rtwo\nthree\tfour" <> <<1>> <> String.duplicate("x", 160)

    log =
      capture_log([level: :debug], fn ->
        Telemetry.handle_semantic_event(
          [:req_llm, :request, :stop],
          %{duration: 1},
          %{
            request_id: unsafe,
            request_options: %{"conversation_id" => "thread-1"},
            model: %{id: "contract:model"},
            usage: %{"tokens" => %{"output_tokens" => 7}}
          },
          nil
        )
      end)

    assert log =~ "event=request.stop"
    assert log =~ "model=contract:model"
    assert log =~ "conversation_id=thread-1"
    assert log =~ "\\n"
    assert log =~ "..."

    Application.put_env(:jido, :ai_telemetry, :invalid)
    assert capture_log(fn -> Telemetry.handle_semantic_event([:unrelated], %{}, %{}, nil) end) == ""
  end

  @tag obligation: ["jido_ai.observability.I3", "jido_ai.observability.I4"]
  test "OpenTelemetry owns agent, reasoning, and tool span lifecycle without leaking context" do
    previous_tracer = :opentelemetry.get_tracer()
    previous_config = Application.fetch_env(:jido, :ai_opentelemetry)
    previous_context = :otel_ctx.attach(:otel_ctx.new())

    assert :opentelemetry.set_default_tracer({TestTracer, self()})
    Application.put_env(:jido, :ai_opentelemetry, %{enabled: true})

    on_exit(fn ->
      :otel_ctx.detach(previous_context)
      :opentelemetry.set_default_tracer(previous_tracer)

      case previous_config do
        {:ok, config} -> Application.put_env(:jido, :ai_opentelemetry, config)
        :error -> Application.delete_env(:jido, :ai_opentelemetry)
      end
    end)

    assert OpenTelemetry.enabled?()

    turn_id = "otel-turn-#{System.unique_integer([:positive])}"
    agent_metadata = %{turn_id: turn_id, agent_name: "contract", status: :failed}

    assert :ok = OpenTelemetry.handle_event([:jido, :ai, :agent, :start], %{}, agent_metadata, nil)
    assert :ok = OpenTelemetry.handle_event([:jido, :ai, :agent, :start], %{}, agent_metadata, nil)

    before = :otel_tracer.current_span_ctx()

    assert :inside_agent =
             Telemetry.with_agent_span(%{turn_id: turn_id}, fn ->
               refute :otel_tracer.current_span_ctx() == before
               :inside_agent
             end)

    operation_id = "operation-#{System.unique_integer([:positive])}"

    reasoning_metadata = %{
      reasoning_operation_id: operation_id,
      reasoning_method: :contract,
      turn_id: turn_id,
      status: :error
    }

    assert :ok =
             OpenTelemetry.handle_event(
               [:jido, :ai, :reasoning, :start],
               %{},
               reasoning_metadata,
               nil
             )

    assert :inside_reasoning =
             OpenTelemetry.with_reasoning_span(operation_id, fn -> :inside_reasoning end)

    attempt_id = "attempt-#{System.unique_integer([:positive])}"
    tool_metadata = %{attempt_id: attempt_id, turn_id: turn_id, tool_name: "contract_tool"}
    assert :ok = OpenTelemetry.handle_event([:jido, :ai, :tool, :start], %{}, tool_metadata, nil)

    assert :ok =
             OpenTelemetry.handle_event(
               [:jido, :ai, :tool, :stop],
               %{},
               Map.merge(tool_metadata, %{status: :error, error_type: 503}),
               nil
             )

    assert :ok =
             OpenTelemetry.handle_event(
               [:jido, :ai, :reasoning, :stop],
               %{},
               reasoning_metadata,
               nil
             )

    assert :ok =
             OpenTelemetry.handle_event(
               [:jido, :ai, :agent, :stop],
               %{},
               agent_metadata,
               nil
             )

    assert :ok = OpenTelemetry.handle_event([:jido, :ai, :tool, :start], %{}, %{}, nil)
    assert :ok = OpenTelemetry.handle_event([:jido, :ai, :tool, :stop], %{}, %{}, nil)
    assert :ok = OpenTelemetry.expire_span(:unused, :invalid)

    events = receive_otel([])
    assert Enum.any?(events, &match?({:otel_status, _ids, :error, "503"}, &1))
    assert Enum.any?(events, &match?({:otel_status, _ids, :error, "jido.ai.reasoning.error"}, &1))

    Application.put_env(:jido, :ai_opentelemetry, %{enabled: false})
    refute OpenTelemetry.enabled?()
    assert :ok = OpenTelemetry.attach()
  end

  @tag obligation: "jido_ai.observability.I5"
  test "correlation sweep handles throwing cleanup callbacks and reports a bounded size" do
    key = {:contract_cleanup, System.unique_integer([:positive])}
    assert CorrelationStore.put_new(key, :value, on_expire: {CleanupProbe, :throw})
    assert CorrelationStore.prune_stale(0) >= 1
    assert is_integer(CorrelationStore.size())

    assert {:noreply, state} =
             CorrelationStore.handle_info(:sweep, %{ttl_ms: 0, sweep_interval_ms: 60_000})

    assert state == %{ttl_ms: 0, sweep_interval_ms: 60_000}
  end

  defp receive_telemetry(events) do
    receive do
      {:contract_telemetry, event, measurements, metadata} ->
        receive_telemetry([{event, measurements, metadata} | events])
    after
      20 -> Enum.reverse(events)
    end
  end

  defp find_event(events, name), do: Enum.find(events, &(elem(&1, 0) == name))

  defp receive_otel(events) do
    receive do
      {:otel_start, _span, _parent, _name, _opts} = event -> receive_otel([event | events])
      {:otel_set_attributes, _ids, _attributes} = event -> receive_otel([event | events])
      {:otel_status, _ids, _code, _description} = event -> receive_otel([event | events])
      {:otel_end, _ids, _timestamp} = event -> receive_otel([event | events])
    after
      20 -> Enum.reverse(events)
    end
  end
end
