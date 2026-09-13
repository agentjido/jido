defmodule JidoTest.Telemetry.OpenTelemetryTest do
  use ExUnit.Case, async: false

  alias Jido.Signal
  alias Jido.Telemetry.OpenTelemetry
  alias Jido.Telemetry.Semantic
  alias Jido.Tracing.Context
  alias JidoTest.OpenTelemetryTracer, as: TestTracer

  setup do
    previous_tracer = :opentelemetry.get_tracer()
    previous_config = Application.fetch_env(:jido, :opentelemetry)
    previous_context = :otel_ctx.attach(:otel_ctx.new())

    assert :opentelemetry.set_default_tracer({TestTracer, self()})
    Application.delete_env(:jido, :opentelemetry)
    Context.clear()

    on_exit(fn ->
      Context.clear()
      :otel_ctx.detach(previous_context)
      :opentelemetry.set_default_tracer(previous_tracer)

      case previous_config do
        {:ok, config} -> Application.put_env(:jido, :opentelemetry, config)
        :error -> Application.delete_env(:jido, :opentelemetry)
      end
    end)

    :ok
  end

  test "the bridge normalizes scalar attributes and drops unsupported values" do
    span =
      OpenTelemetry.start(
        [:jido, :topology, :operation],
        %{
          "external" => "ignored",
          topology_operation: :repair,
          schema_version: 1,
          trace_id: "trace",
          span_id: "span",
          parent_span_id: "parent",
          error_code: :conflict,
          ready?: true,
          absent: nil,
          nested: %{private: true},
          fractional: 0.5
        },
        %{count: 2, duration: 3, monotonic_time: 4, system_time: 5}
      )

    assert_receive {:otel_start, _ctx, _parent, "jido.topology.repair", opts}

    assert opts.attributes == %{
             "jido.topology.operation" => "repair",
             "jido.schema.version" => 1,
             "jido.trace.id" => "trace",
             "jido.span.id" => "span",
             "jido.parent_span.id" => "parent",
             "jido.error.code" => "conflict",
             "jido.ready" => true,
             "jido.count" => 2
           }

    assert :ok =
             OpenTelemetry.finish(span, :stop, %{status: :error, error_type: "storage"}, %{}, 99)

    ids = TestTracer.ids(span.span_ctx)
    assert_receive {:otel_set_attributes, ^ids, %{"error.type" => "storage"}}
    assert_receive {:otel_status, ^ids, :error}
    assert_receive {:otel_end, ^ids, 99}
  end

  test "direct bridge spans accept explicit parents and links" do
    parent = OpenTelemetry.start([:jido, :parent], %{}, %{})
    assert_receive {:otel_start, parent_ctx, _, "jido.parent", _}
    parent_ids = TestTracer.ids(parent_ctx)
    assert :ok = OpenTelemetry.finish(parent, :stop, %{}, %{}, 10)

    child = OpenTelemetry.start([:jido, :child], %{}, %{}, parent_span: parent)
    assert_receive {:otel_start, _, actual_parent, "jido.child", _}
    assert TestTracer.ids(actual_parent) == parent_ids
    assert :ok = OpenTelemetry.finish(child, :stop, %{}, %{}, 11)

    assert :ok =
             OpenTelemetry.point([:jido, :point], %{}, %{},
               parent_span: parent,
               link_span: parent
             )

    assert_receive {:otel_start, point, actual_parent, "jido.point", opts}
    assert TestTracer.ids(actual_parent) == parent_ids
    assert [%{trace_id: trace_id, span_id: span_id}] = opts.links
    assert %{trace_id: trace_id, span_id: span_id} == Map.take(parent_ids, [:trace_id, :span_id])
    ids = TestTracer.ids(point)
    assert_receive {:otel_end, ^ids, timestamp}
    assert timestamp == opts.start_time
    refute :otel_span.is_valid(:otel_tracer.current_span_ctx())
  end

  test "missing carriers do not install context and callback faults restore the caller context" do
    before = OpenTelemetry.current_context()

    for carrier <- [nil, :invalid, %{}, %{traceparent: 123, tracestate: [:invalid]}] do
      assert OpenTelemetry.context_from_trace(carrier) == nil
      assert OpenTelemetry.restore_trace_context(carrier) == nil
    end

    assert OpenTelemetry.with_context(nil, fn -> :returned end) == :returned
    assert OpenTelemetry.detach_trace_context(nil) == :ok
    incoming = Jido.Signal.Trace.new(trace_flags: "01")

    context =
      OpenTelemetry.context_from_trace(%{traceparent: Jido.Signal.Trace.to_traceparent(incoming)})

    assert_raise RuntimeError, "work failed", fn ->
      OpenTelemetry.with_context(context, fn ->
        assert :otel_span.hex_trace_id(:otel_tracer.current_span_ctx()) == incoming.trace_id
        raise "work failed"
      end)
    end

    assert OpenTelemetry.current_context() == before
  end

  test "configuration maps disable tracing and malformed configuration fails closed" do
    Application.put_env(:jido, :opentelemetry, %{enabled: false})
    refute OpenTelemetry.enabled?()
    assert OpenTelemetry.start([:jido, :disabled], %{}, %{}) == nil
    assert OpenTelemetry.current_context() == nil
    assert OpenTelemetry.point([:jido, :disabled], %{}, %{}) == :ok
    assert OpenTelemetry.finish(nil, :stop, %{}, %{}, 0) == :ok

    Application.put_env(:jido, :opentelemetry, :default)
    assert OpenTelemetry.enabled?()
    Application.put_env(:jido, :opentelemetry, [:invalid | :tail])
    refute OpenTelemetry.enabled?()
  end

  test "bad event names do not interrupt the caller or alter its context" do
    before = OpenTelemetry.current_context()
    assert OpenTelemetry.start(["not-an-atom"], %{}, %{}) == nil
    assert OpenTelemetry.point(["not-an-atom"], %{}, %{}) == :ok
    assert OpenTelemetry.current_context() == before
  end

  test "exception event and status failures still end spans and restore context" do
    for callback <- [:add_event, :set_status] do
      assert :opentelemetry.set_default_tracer({TestTracer, %{owner: self(), fail: callback}})
      before = OpenTelemetry.current_context()
      span = OpenTelemetry.start([:jido, :fault], %{}, %{})
      ids = TestTracer.ids(span.span_ctx)
      assert :ok = OpenTelemetry.finish(span, :exception, %{status: :error}, %{}, 12)
      assert_receive {:otel_end, ^ids, 12}
      assert OpenTelemetry.current_context() == before
    end
  end

  test "an end-span failure restores the caller context" do
    assert :opentelemetry.set_default_tracer({TestTracer, %{owner: self(), fail: :end_span}})
    before = OpenTelemetry.current_context()
    span = OpenTelemetry.start([:jido, :fault], %{}, %{})
    assert :otel_span.is_valid(span.span_ctx)
    refute OpenTelemetry.current_context() == before

    assert :ok = OpenTelemetry.finish(span, :stop, %{status: :ok}, %{}, 12)
    assert OpenTelemetry.current_context() == before
  end

  test "semantic spans use bounded names and attributes" do
    assert Jido.Telemetry.open_telemetry?()

    span =
      Semantic.start(
        [:jido, :agent, :turn],
        %{agent_id: "agent-1", stage: :evaluate, private: "secret"},
        %{state_version: 3, private_count: 99}
      )

    assert_receive {:otel_start, otel_span, parent, "jido.agent.turn", start_opts}
    refute :otel_span.is_valid(parent)
    assert TestTracer.ids(otel_span) == TestTracer.ids(span.otel.span_ctx)
    assert start_opts.kind == :internal
    assert start_opts.attributes["jido.agent.id"] == "agent-1"
    assert start_opts.attributes["jido.stage"] == "evaluate"
    assert start_opts.attributes["jido.state.version"] == 3
    refute Map.has_key?(start_opts.attributes, "jido.private")
    refute Map.has_key?(start_opts.attributes, "jido.private.count")

    assert :ok =
             Semantic.finish(span, %{status: :ok, stage: :commit}, %{state_version_after: 4})

    span_ids = TestTracer.ids(otel_span)
    assert_receive {:otel_set_attributes, ^span_ids, final_attributes}
    assert final_attributes["jido.status"] == "ok"
    assert final_attributes["jido.stage"] == "commit"
    assert final_attributes["jido.state.version.after"] == 4
    assert_receive {:otel_end, ^span_ids, ended_at} when is_integer(ended_at)
    refute_received {:otel_status, ^span_ids, _status}

    assert :ok = Semantic.finish(span, %{status: :error})
    refute_received {:otel_end, ^span_ids, _timestamp}
  end

  test "exceptions set error status without recording raw exception data" do
    span = Semantic.start([:jido, :agent, :directive], %{directive_module: __MODULE__})
    assert_receive {:otel_start, otel_span, _parent, "jido.agent.directive", _opts}
    span_ids = TestTracer.ids(otel_span)

    assert :ok =
             Semantic.finish(
               span,
               %{status: :error, error_type: :internal, kind: :error, private: "secret"},
               %{},
               :exception
             )

    assert_receive {:otel_set_attributes, ^span_ids, attributes}
    assert attributes["error.type"] == "internal"
    assert attributes["jido.error.type"] == "internal"
    refute attributes |> inspect() |> String.contains?("secret")

    assert_receive {:otel_event, ^span_ids, "exception", event_attributes}
    assert event_attributes["exception.type"] == "internal"
    assert event_attributes["jido.error.kind"] == "error"
    refute Map.has_key?(event_attributes, "exception.message")
    refute Map.has_key?(event_attributes, "exception.stacktrace")
    assert_receive {:otel_status, ^span_ids, :error}
    assert_receive {:otel_end, ^span_ids, _timestamp}
  end

  test "operation names are bounded by the semantic vocabulary" do
    lifecycle = Semantic.start([:jido, :agent, :lifecycle], %{operation: :activate})
    assert_receive {:otel_start, _span, _parent, "jido.agent.lifecycle.activate", _opts}
    Semantic.finish(lifecycle, %{status: :ok})
    assert_receive {:otel_end, _ids, _timestamp}

    persistence = Semantic.start([:jido, :persistence, :operation], %{operation: :load})
    assert_receive {:otel_start, _span, _parent, "jido.persistence.load", _opts}
    Semantic.finish(persistence, %{status: :ok})
    assert_receive {:otel_end, _ids, _timestamp}
  end

  test "settlement is a zero-duration span linked to its completed Turn" do
    turn = Semantic.start([:jido, :agent, :turn], %{turn_id: "turn-1"})
    assert_receive {:otel_start, turn_span, _parent, "jido.agent.turn", _opts}
    turn_ids = TestTracer.ids(turn_span)
    Semantic.finish(turn, %{status: :ok, stage: :commit})
    assert_receive {:otel_end, ^turn_ids, _timestamp}

    assert :ok =
             Semantic.point(
               [:jido, :agent, :turn, :settled],
               %{turn_id: "turn-1", status: :ok, stage: :directive},
               %{directive_completed: 1},
               link_span: turn
             )

    assert_receive {:otel_start, point_span, _parent, "jido.agent.turn.settled", opts}
    assert [%{trace_id: trace_id, span_id: span_id}] = opts.links
    assert trace_id == turn_ids.trace_id
    assert span_id == turn_ids.span_id

    point_ids = TestTracer.ids(point_span)
    assert_receive {:otel_end, ^point_ids, point_end}
    assert point_end == opts.start_time
  end

  test "W3C context crosses Signal and task boundaries" do
    incoming = Jido.Signal.Trace.new(trace_flags: "01", tracestate: "vendor=value")
    source = Signal.new!("test.trace.source", %{}, source: "/test")
    assert {:ok, source} = Jido.Signal.Trace.put(source, incoming)
    trace = Context.begin_turn(source)

    outer = Semantic.start([:jido, :agent, :turn], Map.put(trace, :turn_id, "turn-1"))
    assert_receive {:otel_start, outer_span, remote_parent, "jido.agent.turn", _opts}
    outer_ids = TestTracer.ids(outer_span)
    assert :otel_span.hex_trace_id(remote_parent) == incoming.trace_id
    assert :otel_span.hex_span_id(remote_parent) == incoming.span_id
    assert outer.trace.trace_id == outer_ids.hex_trace_id
    assert outer.trace.span_id == outer_ids.hex_span_id
    assert outer.trace.parent_span_id == incoming.span_id
    Context.put(outer.trace)

    captured = Context.capture()

    task =
      Task.async(fn ->
        Context.with_context(captured, fn ->
          child = Semantic.start([:jido, :agent, :directive], %{directive_module: __MODULE__})
          Semantic.finish(child, %{status: :ok})
        end)
      end)

    assert :ok = Task.await(task)
    assert_receive {:otel_start, child_span, child_parent, "jido.agent.directive", _opts}
    assert TestTracer.ids(child_parent) == outer_ids
    child_ids = TestTracer.ids(child_span)
    assert_receive {:otel_end, ^child_ids, _timestamp}

    target = Signal.new!("test.trace.target", %{}, source: "/test")
    assert {:ok, traced_target} = Context.propagate_to(target, source.id)
    propagated = Jido.Signal.Trace.get(traced_target)
    assert propagated.trace_id == outer_ids.hex_trace_id
    assert propagated.span_id == outer_ids.hex_span_id
    assert propagated.trace_flags == "01"

    Semantic.finish(outer, %{status: :ok, stage: :commit})
    assert_receive {:otel_end, ^outer_ids, _timestamp}
  end

  test "an untraced Signal lets the SDK make the root sampling decision" do
    source = Signal.new!("test.trace.source", %{}, source: "/test")
    trace = Context.begin_turn(source)
    span = Semantic.start([:jido, :agent, :turn], trace)

    assert_receive {:otel_start, otel_span, parent, "jido.agent.turn", _opts}
    refute :otel_span.is_valid(parent)
    assert span.trace.trace_id == TestTracer.ids(otel_span).hex_trace_id
    assert span.trace.trace_flags == "01"

    Semantic.finish(span, %{status: :ok})
  end

  test "configuration can disable OpenTelemetry without disabling semantic events" do
    Application.put_env(:jido, :opentelemetry, enabled: false)
    refute OpenTelemetry.enabled?()
    event = [:jido, :agent, :turn, :stop]
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        event,
        fn event, measurements, metadata, owner ->
          send(owner, {:semantic_event, event, measurements, metadata})
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    span = Semantic.start([:jido, :agent, :turn], %{turn_id: "turn-1"})
    assert span.otel == nil
    assert :ok = Semantic.finish(span, %{status: :ok, stage: :commit})
    assert_receive {:semantic_event, ^event, %{duration: duration}, %{status: :ok}}
    assert is_integer(duration)
    refute_received {:otel_start, _span, _parent, _name, _opts}
  end

  test "the API no-op tracer leaves semantic spans active" do
    assert :opentelemetry.set_default_tracer({:otel_tracer_noop, []})
    refute OpenTelemetry.enabled?()

    span = Semantic.start([:jido, :agent, :turn], %{turn_id: "turn-1"})

    assert span.otel == nil
    assert :ok = Semantic.finish(span, %{status: :ok, stage: :commit})
  end

  test "a tracer callback failure does not stop semantic emission or leak context" do
    tracer = {TestTracer, %{owner: self(), fail: :set_attributes}}
    assert :opentelemetry.set_default_tracer(tracer)
    event = [:jido, :agent, :turn, :stop]
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        event,
        fn event, measurements, metadata, owner ->
          send(owner, {:semantic_event, event, measurements, metadata})
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    span = Semantic.start([:jido, :agent, :turn], %{turn_id: "turn-1"})
    assert_receive {:otel_start, _otel_span, _parent, "jido.agent.turn", _opts}
    assert :ok = Semantic.finish(span, %{status: :ok, stage: :commit})
    assert_receive {:semantic_event, ^event, %{duration: _duration}, %{status: :ok}}
    refute :otel_span.is_valid(:otel_tracer.current_span_ctx())
  end
end
