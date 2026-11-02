defmodule Jido.Telemetry.Semantic do
  @moduledoc false

  alias Jido.Error
  alias Jido.Signal.Trace, as: SignalTrace
  alias Jido.Telemetry.OpenTelemetry

  @schema_version 1

  @id_keys ~w(agent_namespace agent_id activation_id turn_id source_signal_id signal_id signal_type trace_id span_id parent_span_id causation_id cause_turn_id child_activation_id topology_id node_id)a
  @module_keys ~w(agent_module directive_module adapter_module plugin_module facet_module)a
  @boolean_keys [:committed?, :retryable?]
  @status_values ~w(ok error cancelled timed_out conflict indeterminate not_found rejected)a
  @stage_values ~w(evaluate commit after_commit directive)a
  @kind_values ~w(error throw exit)a
  @operation_values ~w(activate stop hibernate thaw load compare_and_swap delete)a
  @admission_values ~w(deadline_expired overloaded)a
  @persistence_values ~w(commit activate stop hibernate thaw manual topology)a
  @topology_values ~w(activate repair update place cleanup)a

  @signed_measurements [:system_time, :monotonic_time]
  @count_measurements ~w(count duration state_version state_version_before state_version_after directive_count directive_index directive_completed directive_failed directive_skipped queue_depth queue_limit wait_duration expected_revision revision_before revision_after target_revision component_count ready_count failed_count epoch)a
  @trace_metadata_keys [:trace_id, :span_id, :parent_span_id, :causation_id]
  @trace_carrier_keys [
    :trace_id,
    :span_id,
    :parent_span_id,
    :causation_id,
    :traceparent,
    :tracestate
  ]
  @log_scope_key {:jido, :semantic_log_scope}

  @type span :: %{
          required(:prefix) => [atom()],
          required(:metadata) => map(),
          required(:trace) => map() | nil,
          required(:at) => integer(),
          optional(:terminal_guard) => :atomics.atomics_ref(),
          optional(:log_scope) => atom() | nil,
          optional(:otel) => OpenTelemetry.Span.t() | nil
        }

  @doc false
  def schema_version, do: @schema_version

  @doc false
  def start(prefix, metadata, measurements \\ %{}, opts \\ []) do
    at = System.monotonic_time()
    metadata = safe_metadata(metadata)
    trace = Map.take(metadata, @trace_carrier_keys)
    log_scope = log_scope(metadata)
    metadata = metadata |> Map.drop(@trace_carrier_keys) |> normalize_metadata()
    measurements = normalize_measurements(measurements)

    otel = OpenTelemetry.start(prefix, metadata, measurements, put_option(opts, :start_time, at))
    trace = Map.merge(valid_trace(trace) || %{}, OpenTelemetry.trace_context(otel) || %{})
    trace = if map_size(trace) == 0, do: nil, else: trace

    metadata =
      Map.merge(metadata, normalize_metadata(Map.take(trace || %{}, @trace_metadata_keys)))

    span = %{
      prefix: prefix,
      metadata: metadata,
      trace: trace,
      at: at,
      terminal_guard: :atomics.new(1, []),
      log_scope: log_scope,
      otel: otel
    }

    emit_normalized(
      event_name(prefix, :start),
      measurements
      |> Map.merge(%{monotonic_time: at, system_time: System.system_time()}),
      metadata,
      log_scope
    )

    span
  end

  @doc false
  def finish(span, metadata \\ %{}, measurements \\ %{}, ending \\ :stop)
  def finish(nil, _metadata, _measurements, _ending), do: :ok

  def finish(
        %{prefix: prefix, metadata: base, at: started} = span,
        metadata,
        measurements,
        ending
      ) do
    if claim_terminal?(span) do
      duration = max(System.monotonic_time() - started, 0)
      measurements = measurements |> normalize_measurements() |> Map.put(:duration, duration)
      metadata = Map.merge(base, normalize_metadata(metadata))
      ended_at = started + duration

      OpenTelemetry.finish(Map.get(span, :otel), ending, metadata, measurements, ended_at)

      emit_normalized(
        event_name(prefix, ending),
        measurements,
        metadata,
        Map.get(span, :log_scope)
      )
    end

    :ok
  end

  @doc false
  def point(event, metadata, measurements \\ %{}, opts \\ []) do
    at = System.monotonic_time()

    measurements =
      measurements
      |> normalize_measurements()
      |> Map.put_new(:monotonic_time, at)
      |> Map.put_new(:system_time, System.system_time())

    log_scope = log_scope(metadata)
    metadata = normalize_metadata(metadata)

    OpenTelemetry.point(event, metadata, measurements, put_option(opts, :at, at))
    emit_normalized(event, measurements, metadata, log_scope)
  end

  @doc false
  def with_span(prefix, metadata, start_measurements, fun, result_measurements \\ fn _ -> %{} end) do
    span = start(prefix, metadata, start_measurements)

    try do
      result = fun.()
      finish(span, result_metadata(result), safe_result_measurements(result_measurements, result))
      result
    catch
      kind, reason ->
        finish(
          span,
          error_metadata(reason) |> Map.merge(%{status: :error, kind: kind}),
          %{},
          :exception
        )

        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  @doc false
  def result_metadata(:ok), do: %{status: :ok}
  def result_metadata({:ok, _value}), do: %{status: :ok}
  def result_metadata({:ok, _value, _revision}), do: %{status: :ok}
  def result_metadata({:error, :not_found}), do: %{status: :not_found}
  def result_metadata({:error, :deleted}), do: %{status: :not_found}
  def result_metadata({:error, :conflict}), do: %{status: :conflict}
  def result_metadata({:error, :indeterminate}), do: %{status: :indeterminate}
  def result_metadata({:error, {:indeterminate, _reason}}), do: %{status: :indeterminate}
  def result_metadata({:error, {:rejected, _reason}}), do: %{status: :rejected}
  def result_metadata({:error, reason}), do: error_metadata(reason) |> Map.put(:status, :error)
  def result_metadata(_result), do: %{status: :ok}

  @doc false
  def error_metadata(reason) do
    public = Error.to_map(reason)

    %{error_type: public.type, retryable?: public.retryable?}
    |> maybe_put(:error_code, Error.code(reason))
  end

  @doc false
  def normalize_metadata(metadata) when is_map(metadata) do
    metadata
    |> Enum.reduce(%{schema_version: @schema_version}, &normalize_field/2)
  end

  def normalize_metadata(_metadata), do: %{schema_version: @schema_version}

  @doc false
  def normalize_measurements(measurements) when is_map(measurements) do
    Enum.reduce(measurements, %{}, fn
      {key, value}, acc when key in @signed_measurements and is_integer(value) ->
        Map.put(acc, key, value)

      {key, value}, acc when key in @count_measurements and is_integer(value) and value >= 0 ->
        Map.put(acc, key, value)

      _field, acc ->
        acc
    end)
  end

  def normalize_measurements(_measurements), do: %{}

  defp normalize_field({:schema_version, _value}, acc), do: acc

  defp normalize_field({key, value}, acc) when key in @id_keys,
    do: put_bounded_string(acc, key, value, 256)

  defp normalize_field({:agent_partition, value}, acc),
    do: put_bounded_string(acc, :agent_partition, value, 128)

  defp normalize_field({:agent_name, value}, acc),
    do: put_bounded_string(acc, :agent_name, value, 256)

  defp normalize_field({key, value}, acc)
       when key in @module_keys and is_atom(value) and not is_nil(value),
       do: Map.put(acc, key, value)

  defp normalize_field({key, value}, acc) when key in @boolean_keys and is_boolean(value),
    do: Map.put(acc, key, value)

  defp normalize_field({:status, value}, acc) when value in @status_values,
    do: Map.put(acc, :status, value)

  defp normalize_field({:stage, value}, acc) when value in @stage_values,
    do: Map.put(acc, :stage, value)

  defp normalize_field({:kind, value}, acc) when value in @kind_values,
    do: Map.put(acc, :kind, value)

  defp normalize_field({:operation, value}, acc) when value in @operation_values,
    do: Map.put(acc, :operation, value)

  defp normalize_field({:admission_reason, value}, acc) when value in @admission_values,
    do: Map.put(acc, :admission_reason, value)

  defp normalize_field({:persistence_reason, value}, acc) when value in @persistence_values,
    do: Map.put(acc, :persistence_reason, value)

  defp normalize_field({:topology_operation, value}, acc) when value in @topology_values,
    do: Map.put(acc, :topology_operation, value)

  defp normalize_field({:component_kind, value}, acc)
       when is_atom(value) and not is_nil(value),
       do: Map.put(acc, :component_kind, value)

  defp normalize_field({:error_type, value}, acc) when is_atom(value) and not is_nil(value),
    do: Map.put(acc, :error_type, value)

  defp normalize_field({:error_code, value}, acc) do
    if value in Error.stable_codes(), do: Map.put(acc, :error_code, value), else: acc
  end

  defp normalize_field(_field, acc), do: acc

  defp put_bounded_string(acc, key, value, limit)
       when is_binary(value) and byte_size(value) <= limit do
    if String.valid?(value), do: Map.put(acc, key, value), else: acc
  end

  defp put_bounded_string(acc, _key, _value, _limit), do: acc

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp safe_metadata(metadata) when is_map(metadata), do: metadata
  defp safe_metadata(_metadata), do: %{}

  defp put_option(opts, key, value) do
    if Keyword.keyword?(opts), do: Keyword.put(opts, key, value), else: [{key, value}]
  end

  defp safe_result_measurements(fun, result) do
    fun.(result)
  rescue
    _error -> %{}
  catch
    _kind, _reason -> %{}
  end

  defp event_name(prefix, ending) when is_list(prefix) and is_atom(ending) do
    if Enum.all?(prefix, &is_atom/1), do: prefix ++ [ending]
  end

  defp event_name(_prefix, _ending), do: nil

  defp log_scope(%{jido_instance: instance}) when is_atom(instance),
    do: instance

  defp log_scope(_metadata), do: nil

  defp valid_trace(%{traceparent: traceparent} = trace) do
    case SignalTrace.from_traceparent(traceparent, Map.get(trace, :tracestate)) do
      {:ok, w3c} ->
        %{
          trace_id: w3c.trace_id,
          span_id: w3c.span_id,
          trace_flags: w3c.trace_flags,
          traceparent: SignalTrace.to_traceparent(w3c)
        }
        |> Map.merge(Map.take(trace, [:parent_span_id, :causation_id]))
        |> maybe_put(:tracestate, w3c.tracestate)

      {:error, :invalid_traceparent} ->
        nil
    end
  end

  defp valid_trace(_trace), do: nil

  defp claim_terminal?(%{terminal_guard: guard}),
    do: :atomics.compare_exchange(guard, 1, 0, 1) == :ok

  defp emit_normalized(nil, _measurements, _metadata, _log_scope), do: :ok

  defp emit_normalized(event, measurements, metadata, nil) do
    :telemetry.execute(event, measurements, metadata)
    :ok
  catch
    _, _ -> :ok
  end

  defp emit_normalized(event, measurements, metadata, log_scope) do
    previous = Process.get(@log_scope_key)
    Process.put(@log_scope_key, log_scope)

    try do
      :telemetry.execute(event, measurements, metadata)
      :ok
    after
      if previous,
        do: Process.put(@log_scope_key, previous),
        else: Process.delete(@log_scope_key)
    end
  catch
    _, _ -> :ok
  end
end
