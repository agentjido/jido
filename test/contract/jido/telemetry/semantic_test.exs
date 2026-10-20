defmodule JidoTest.Telemetry.SemanticTest do
  use Covenant.Case, component: "jido.telemetry", async: false

  @moduletag obligation: ["jido.telemetry.I2", "jido.telemetry.I3"]

  alias Jido.Telemetry.Semantic

  test "metadata normalization keeps only bounded semantic fields" do
    invalid_utf8 = <<255>>

    assert Semantic.normalize_metadata(%{
             schema_version: 99,
             agent_namespace: "shop",
             agent_partition: "west",
             agent_id: "order-1",
             agent_module: __MODULE__,
             status: :conflict,
             stage: :commit,
             operation: :compare_and_swap,
             error_code: :persistence_callback_failed,
             retryable?: false,
             trace_id: String.duplicate("x", 257),
             signal_type: invalid_utf8,
             partition: %{private: self()},
             raw_error: RuntimeError.exception("private")
           }) == %{
             schema_version: 1,
             agent_namespace: "shop",
             agent_partition: "west",
             agent_id: "order-1",
             agent_module: __MODULE__,
             status: :conflict,
             stage: :commit,
             operation: :compare_and_swap,
             error_code: :persistence_callback_failed,
             retryable?: false
           }

    refute Map.has_key?(
             Semantic.normalize_metadata(%{
               agent_partition: String.duplicate("p", 129)
             }),
             :agent_partition
           )
  end

  test "measurement normalization keeps only approved integers" do
    assert Semantic.normalize_measurements(%{
             system_time: -1,
             duration: 3,
             revision_after: 2,
             queue_depth: 0,
             failed_count: -1,
             ratio: 0.5,
             private_count: 9
           }) == %{
             system_time: -1,
             duration: 3,
             revision_after: 2,
             queue_depth: 0
           }

    assert Semantic.normalize_measurements(nil) == %{}
    assert Semantic.normalize_metadata(nil) == %{schema_version: Semantic.schema_version()}

    assert Semantic.normalize_metadata(%{component_kind: :agent}) ==
             %{schema_version: 1, component_kind: :agent}
  end

  test "normalization enforces each fixed vocabulary and scalar family" do
    vocabularies = [
      status: [
        :ok,
        :error,
        :cancelled,
        :timed_out,
        :conflict,
        :indeterminate,
        :not_found,
        :rejected
      ],
      stage: [:evaluate, :commit, :after_commit, :directive],
      kind: [:error, :throw, :exit],
      operation: [:activate, :stop, :hibernate, :thaw, :load, :compare_and_swap, :delete],
      admission_reason: [:deadline_expired, :overloaded],
      persistence_reason: [:commit, :activate, :stop, :hibernate, :thaw, :manual, :topology],
      topology_operation: [:activate, :repair, :update, :place, :cleanup]
    ]

    for {key, values} <- vocabularies, value <- values do
      assert Semantic.normalize_metadata(%{key => value}) ==
               %{key => value, schema_version: 1}
    end

    for {key, _values} <- vocabularies do
      assert Semantic.normalize_metadata(%{key => :private}) == %{schema_version: 1}
    end

    id_keys =
      ~w(agent_namespace agent_id activation_id turn_id source_signal_id signal_id signal_type trace_id span_id parent_span_id causation_id cause_turn_id child_activation_id topology_id node_id)a

    module_keys = ~w(agent_module directive_module adapter_module plugin_module facet_module)a

    for key <- id_keys do
      assert Semantic.normalize_metadata(%{key => "id"}) == %{key => "id", schema_version: 1}
    end

    for key <- module_keys do
      assert Semantic.normalize_metadata(%{key => __MODULE__}) ==
               %{key => __MODULE__, schema_version: 1}

      assert Semantic.normalize_metadata(%{key => "private"}) == %{schema_version: 1}
    end

    for key <- [:committed?, :retryable?], value <- [true, false] do
      assert Semantic.normalize_metadata(%{key => value}) == %{key => value, schema_version: 1}
    end

    assert Semantic.normalize_metadata(%{agent_id: String.duplicate("a", 256)}).agent_id ==
             String.duplicate("a", 256)

    refute Map.has_key?(
             Semantic.normalize_metadata(%{agent_id: String.duplicate("a", 257)}),
             :agent_id
           )

    assert Semantic.normalize_metadata(%{agent_partition: String.duplicate("p", 128)}).agent_partition ==
             String.duplicate("p", 128)

    assert Semantic.normalize_metadata(%{
             component_kind: :agent,
             error_type: :timeout,
             error_code: :agent_turn_timeout
           }) == %{
             schema_version: 1,
             component_kind: :agent,
             error_type: :timeout,
             error_code: :agent_turn_timeout
           }

    assert Semantic.normalize_metadata(%{
             component_kind: nil,
             error_type: nil,
             error_code: :private
           }) == %{schema_version: 1}

    count_keys =
      ~w(count duration state_version state_version_before state_version_after directive_count directive_index directive_completed directive_failed directive_skipped queue_depth queue_limit wait_duration expected_revision revision_before revision_after target_revision component_count ready_count failed_count epoch)a

    for key <- [:system_time, :monotonic_time] do
      assert Semantic.normalize_measurements(%{key => -1}) == %{key => -1}
    end

    for key <- count_keys do
      assert Semantic.normalize_measurements(%{key => 0}) == %{key => 0}
      assert Semantic.normalize_measurements(%{key => -1}) == %{}
    end
  end

  test "result metadata classifies returned outcomes without exposing payloads" do
    for result <- [:ok, {:ok, :private}, {:ok, :private, 2}, :ignored] do
      assert Semantic.result_metadata(result) == %{status: :ok}
    end

    for {result, status} <- [
          {{:error, :not_found}, :not_found},
          {{:error, :deleted}, :not_found},
          {{:error, :conflict}, :conflict},
          {{:error, :indeterminate}, :indeterminate},
          {{:error, {:indeterminate, :private}}, :indeterminate},
          {{:error, {:rejected, :private}}, :rejected}
        ] do
      assert Semantic.result_metadata(result) == %{status: status}
    end

    error = Jido.Error.timeout_error("private", timeout: 10)

    assert Semantic.result_metadata({:error, error}) == %{
             status: :error,
             error_type: :timeout,
             retryable?: true
           }
  end

  test "topology operation vocabulary includes update and exact placement" do
    for operation <- [:activate, :repair, :update, :place, :cleanup] do
      assert Semantic.normalize_metadata(%{topology_operation: operation}) == %{
               schema_version: 1,
               topology_operation: operation
             }
    end

    assert Semantic.normalize_metadata(%{topology_operation: :rebalance}) == %{schema_version: 1}
  end

  test "one span emits one terminal semantic event" do
    event = [:jido, :agent, :turn, :stop]
    handler = {__MODULE__, make_ref()}
    count = :atomics.new(1, signed: false)

    :ok =
      :telemetry.attach(
        handler,
        event,
        fn _name, _measurements, metadata, {counter, turn_id} ->
          if metadata[:turn_id] == turn_id, do: :atomics.add(counter, 1, 1)
        end,
        {count, "one"}
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    span = Semantic.start([:jido, :agent, :turn], %{turn_id: "one"})
    assert :ok = Semantic.finish(span, %{status: :ok})
    assert :ok = Semantic.finish(span, %{status: :ok})
    assert :atomics.get(count, 1) == 1
  end

  test "competing finishes emit one terminal semantic event" do
    prefix = [:jido, :agent, :turn]
    handler = {__MODULE__, make_ref()}
    count = :atomics.new(1, signed: false)

    :ok =
      :telemetry.attach_many(
        handler,
        for(ending <- [:stop, :exception], do: prefix ++ [ending]),
        fn _name, _measurements, metadata, {counter, turn_id} ->
          if metadata[:turn_id] == turn_id, do: :atomics.add(counter, 1, 1)
        end,
        {count, "competing"}
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    span = Semantic.start(prefix, %{turn_id: "competing"})
    parent = self()

    tasks =
      for ending <- [:stop, :exception] do
        Task.async(fn ->
          send(parent, {:ready, self()})
          receive do: (:finish -> Semantic.finish(span, %{status: :ok}, %{}, ending))
        end)
      end

    for _task <- tasks, do: assert_receive({:ready, _pid})
    for task <- tasks, do: send(task.pid, :finish)
    for task <- tasks, do: assert(:ok = Task.await(task))

    assert :atomics.get(count, 1) == 1
  end

  test "a returned failure stops a span and an escaping fault reports an exception" do
    handler = {__MODULE__, make_ref()}
    prefix = [:jido, :persistence, :operation]
    events = for ending <- [:start, :stop, :exception], do: prefix ++ [ending]

    :ok =
      :telemetry.attach_many(
        handler,
        events,
        fn event, measurements, metadata, owner ->
          send(owner, {:semantic_event, event, measurements, metadata})
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert {:error, :conflict} =
             Semantic.with_span(prefix, %{operation: :compare_and_swap}, %{}, fn ->
               {:error, :conflict}
             end)

    assert_receive {:semantic_event, [:jido, :persistence, :operation, :start],
                    %{system_time: _, monotonic_time: _}, %{schema_version: 1}}

    assert_receive {:semantic_event, [:jido, :persistence, :operation, :stop],
                    %{duration: duration}, %{status: :conflict}}

    assert duration >= 0

    assert catch_throw(
             Semantic.with_span(prefix, %{operation: :load}, %{}, fn -> throw(:fault) end)
           ) == :fault

    assert_receive {:semantic_event, [:jido, :persistence, :operation, :start], _, _}

    assert_receive {:semantic_event, [:jido, :persistence, :operation, :exception],
                    %{duration: duration}, %{status: :error, kind: :throw}}

    assert duration >= 0
  end

  test "span time, disabled trace data, and nested log scope stay exact" do
    previous = Application.fetch_env(:jido, :opentelemetry)
    Application.put_env(:jido, :opentelemetry, enabled: false)
    on_exit(fn -> restore_env(:jido, :opentelemetry, previous) end)

    trace = Jido.Signal.Trace.new(trace_flags: "01", tracestate: "vendor=value")

    metadata = %{
      trace_id: trace.trace_id,
      span_id: trace.span_id,
      trace_flags: trace.trace_flags,
      traceparent: Jido.Signal.Trace.to_traceparent(trace),
      tracestate: trace.tracestate,
      jido_instance: :inner
    }

    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach_many(
        handler,
        [[:jido, :exact, :start], [:jido, :exact, :stop]],
        fn event, measurements, metadata, owner ->
          send(owner, {:exact_event, event, measurements, metadata})
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    Process.put({:jido, :semantic_log_scope}, :outer)

    span = Semantic.start([:jido, :exact], metadata)
    assert span.trace.tracestate == "vendor=value"
    assert span.trace.trace_flags == "01"
    assert Process.get({:jido, :semantic_log_scope}) == :outer

    assert_receive {:exact_event, [:jido, :exact, :start],
                    %{monotonic_time: started, system_time: system_time}, start_metadata}

    assert started == span.at
    assert is_integer(system_time)
    assert start_metadata.trace_id == trace.trace_id
    assert start_metadata.span_id == trace.span_id

    future_span = %{
      span
      | at: System.monotonic_time() + System.convert_time_unit(1, :second, :native)
    }

    assert :ok = Semantic.finish(future_span, %{status: :ok})

    assert_receive {:exact_event, [:jido, :exact, :stop], %{duration: 0}, %{status: :ok}}
    assert Process.get({:jido, :semantic_log_scope}) == :outer
    Process.delete({:jido, :semantic_log_scope})
  end

  test "a failing handler is contained and detached" do
    event = [:jido, :handler, :point]
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        event,
        fn _event, _measurements, _metadata, _config -> throw(:handler_fault) end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    assert :ok = Semantic.point(event, %{status: :ok})
    refute Enum.any?(:telemetry.list_handlers(event), &(&1.id == handler))
  end

  defp restore_env(app, key, {:ok, value}), do: Application.put_env(app, key, value)
  defp restore_env(app, key, :error), do: Application.delete_env(app, key)
end
