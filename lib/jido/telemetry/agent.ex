defmodule Jido.Telemetry.Agent do
  @moduledoc false

  alias Jido.AgentServer.{ActiveTurn, CreationCause}
  alias Jido.Telemetry.Semantic
  alias Jido.Tracing.Trace

  def identity(data) do
    namespace = safe_namespace(data.jido)

    %{
      agent_namespace: namespace,
      agent_partition: if(is_binary(data.partition), do: data.partition),
      agent_id: data.agent.id,
      agent_module: data.agent.module,
      activation_id: data.activation_id,
      jido_instance: data.jido,
      partition: data.partition
    }
  end

  def lifecycle_metadata(data) do
    cause = if data.parent, do: data.parent.creation_cause
    Map.merge(identity(data), CreationCause.metadata(cause))
  end

  def turn_metadata(data) do
    active = data.active
    signal = active.effective_signal || active.source_signal
    trace = Trace.get(signal) || active.span[:metadata] || %{}

    identity(data)
    |> Map.merge(
      Map.take(trace, [:trace_id, :span_id, :parent_span_id, :causation_id, :sampled?])
    )
    |> Map.merge(%{
      cause_turn_id: Jido.Signal.get_context(signal, "jidocauseturnid"),
      child_activation_id: Jido.Signal.get_context(signal, "jidochildactivation"),
      turn_id: active.turn_id,
      source_signal_id: active.source_signal.id,
      signal_id: signal.id,
      signal_type: signal.type
    })
  end

  def admission_rejected(data, signal, reason) when reason in [:deadline_expired, :overloaded] do
    trace = Trace.get(signal) || %{}

    metadata =
      data
      |> identity()
      |> Map.merge(
        Map.take(trace, [:trace_id, :span_id, :parent_span_id, :causation_id, :sampled?])
      )
      |> Map.merge(%{
        source_signal_id: signal.id,
        signal_id: signal.id,
        signal_type: signal.type,
        status: :rejected,
        admission_reason: reason
      })

    measurements = %{
      queue_depth: MapSet.size(data.postponed_tokens),
      queue_limit: data.max_postponed_signals
    }

    Semantic.point([:jido, :agent, :admission, :rejected], metadata, measurements)
  end

  def start(boundary, metadata, measurements \\ %{}, opts \\ []) do
    Semantic.start([:jido, :agent, boundary], metadata, measurements, opts)
  end

  def finish(span, metadata \\ %{}, measurements \\ %{}, ending \\ :stop)
  def finish(nil, _metadata, _measurements, _ending), do: :ok

  def finish(span, metadata, measurements, ending) do
    Semantic.finish(span, metadata, measurements, ending)
  end

  def with_span(boundary, metadata, fun) do
    span = start(boundary, metadata)

    try do
      result = fun.()
      finish(span, result_metadata(result))
      result
    catch
      kind, reason ->
        finish(
          span,
          Map.merge(error_metadata(reason), %{status: :error, kind: kind}),
          %{},
          :exception
        )

        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  def committed(data, version, directive_count) do
    finish(
      data.active.span,
      Map.merge(turn_metadata(data), %{status: :ok, stage: :commit, committed?: true}),
      %{
        state_version_before: data.active.start_version,
        state_version_after: version,
        directive_count: directive_count
      }
    )
  end

  def settled(data, outcome, kind \\ nil) do
    metadata =
      turn_metadata(data)
      |> Map.merge(%{
        status: status(outcome.status),
        stage: stage(outcome.stage),
        committed?: outcome.committed?
      })
      |> Map.merge(if outcome.error, do: error_metadata(outcome.error), else: %{})
      |> Map.merge(if kind, do: %{kind: kind}, else: %{})

    measurements = %{
      state_version_before: outcome.state_version_before,
      directive_count: outcome.directives.total,
      directive_completed: outcome.directives.completed,
      directive_failed: outcome.directives.failed,
      directive_skipped: outcome.directives.skipped
    }

    measurements =
      if outcome.state_version_after,
        do: Map.put(measurements, :state_version_after, outcome.state_version_after),
        else: measurements

    unless outcome.committed? do
      finish(
        data.active.span,
        metadata,
        measurements,
        if(kind, do: :exception, else: :stop)
      )
    end

    duration = max(System.monotonic_time() - data.active.span.at, 0)

    Semantic.point(
      [:jido, :agent, :turn, :settled],
      metadata,
      Map.put(measurements, :duration, duration),
      link_span: data.active.span
    )
  end

  def interrupted(%{active: nil}, _reason), do: :ok

  def interrupted(data, reason) do
    active = data.active
    stage = if active.committed_version, do: :directive, else: :execute
    outcome = ActiveTurn.outcome(active, data.agent.id, :indeterminate, stage, reason)
    settled(data, outcome, interruption_kind(reason))
  end

  defp interruption_kind(reason) when reason in [:normal, :shutdown], do: nil
  defp interruption_kind({:shutdown, _reason}), do: nil
  defp interruption_kind(_reason), do: :exit

  def result_metadata({:error, reason}) do
    metadata = error_metadata(reason)
    Map.put(metadata, :status, result_error_status(reason, metadata))
  end

  def result_metadata(_result), do: %{status: :ok}

  defp result_error_status(:cancelled, _metadata), do: :cancelled
  defp result_error_status({:parent_down, :cancelled}, _metadata), do: :cancelled

  defp result_error_status({:child_spawn_indeterminate, _, _, _, _}, _metadata),
    do: :indeterminate

  defp result_error_status(_reason, metadata), do: metadata_error_status(metadata)

  defp metadata_error_status(%{error_type: :timeout}), do: :timed_out
  defp metadata_error_status(_metadata), do: :error

  def error_metadata(reason) do
    Semantic.error_metadata(reason)
  end

  defp status(:succeeded), do: :ok
  defp status(:failed), do: :error
  defp status(status), do: status
  defp stage(stage) when stage in [:prepare, :execute, :finalize], do: :evaluate
  defp stage(stage), do: stage

  defp safe_namespace(jido) when is_atom(jido) do
    Jido.namespace(jido)
  rescue
    _error -> nil
  catch
    _kind, _reason -> nil
  end

  defp safe_namespace(_jido), do: nil
end
