defmodule Jido.Plugin.Scheduler.Durable do
  @moduledoc false
  alias Jido.Plugin.Scheduler.{Acknowledge, Occurrence, Queue}
  alias Jido.Signal

  @marker "jidodurabletick"
  @progress [:pending, :last_scheduled_at]
  @trace ~w(id jidotraceid jidospanid jidoparentspanid jidocausationid traceparent tracestate)

  def enabled?(spec), do: Map.get(spec, :delivery) == :durable
  def marked?(signal), do: Signal.get_context(signal, @marker) == true
  def definition(spec), do: Map.drop(spec, @progress)

  def enqueue_signal(job_id, generation, scheduled_at) do
    Signal.new!(
      "jido.scheduler.enqueue",
      %{
        job_id: job_id,
        generation: generation,
        scheduled_at: DateTime.to_iso8601(DateTime.shift_zone!(scheduled_at, "Etc/UTC"))
      },
      source: "/jido/scheduler"
    )
  end

  def replace(nil, spec), do: {:ok, spec}

  def replace(old, spec) do
    cond do
      definition(old) == definition(spec) ->
        {:ok, old}

      not enabled?(old) and not enabled?(spec) ->
        {:ok, spec}

      is_integer(spec[:generation]) and
          (is_nil(old[:generation]) or spec.generation > old.generation) ->
        {:ok, spec}

      true ->
        {:error, :schedule_generation_conflict}
    end
  end

  def update(state, %Queue{} = directive) do
    case Map.get(state.cron, directive.job_id) do
      %{delivery: :durable, generation: generation} = spec
      when generation == directive.generation ->
        with {:ok, next} <- queue(spec, directive) do
          {:ok, put_in(state, [:cron, directive.job_id], next)}
        end

      _ ->
        {:error, :stale_schedule_generation}
    end
  end

  def update(state, %Acknowledge{occurrence_id: id}) do
    case find_pending(state, id) do
      {job_id, _signal} -> {:ok, put_in(state, [:cron, job_id, :pending], nil)}
      nil -> {:error, :unknown_schedule_occurrence}
    end
  end

  def admit(state, signal) do
    with {:ok, occurrence} <- Occurrence.from_signal(signal),
         {_job, pending} <- find_pending(state, occurrence.id),
         true <- payload(pending) == payload(signal) do
      :ok
    else
      _ -> {:error, :stale_or_invalid_schedule_occurrence}
    end
  end

  def pending(state) do
    for {job, %{delivery: :durable, pending: %Signal{} = signal}} <- state.cron, do: {job, signal}
  end

  def validate(spec) do
    if enabled?(spec) do
      validate_progress(spec)
    else
      if Enum.any?(@progress, &Map.has_key?(spec, &1)),
        do: {:error, :unexpected_schedule_progress},
        else: :ok
    end
  end

  defp validate_progress(%{generation: generation, pending: nil, last_scheduled_at: _})
       when is_integer(generation), do: :ok

  defp validate_progress(%{
         generation: generation,
         pending: %Signal{} = pending,
         last_scheduled_at: last
       })
       when is_binary(last) do
    with {:ok, occurrence} <- Occurrence.from_signal(pending),
         true <- occurrence.generation == generation and marked?(pending),
         {:ok, time, 0} <- DateTime.from_iso8601(occurrence.scheduled_at),
         {:ok, last, 0} <- DateTime.from_iso8601(last),
         true <- DateTime.compare(time, last) != :gt do
      :ok
    else
      _ -> {:error, :invalid_pending_occurrence}
    end
  end

  defp validate_progress(_), do: {:error, :invalid_durable_schedule}

  defp queue(spec, directive) do
    {:ok, scheduled_at, 0} = DateTime.from_iso8601(directive.scheduled_at)

    if newer?(scheduled_at, spec.last_scheduled_at) do
      with {:ok, pending} <- keep_or_create(spec.pending, spec.message, directive, scheduled_at) do
        {:ok, %{spec | pending: pending, last_scheduled_at: DateTime.to_iso8601(scheduled_at)}}
      end
    else
      {:ok, spec}
    end
  end

  defp keep_or_create(nil, template, directive, scheduled_at) do
    with {:ok, signal} <-
           Occurrence.attach(
             template,
             directive.scope,
             directive.job_id,
             directive.generation,
             scheduled_at
           ) do
      Signal.put_context(signal, @marker, true)
    end
  end

  defp keep_or_create(pending, _template, _directive, _time), do: {:ok, pending}

  defp newer?(_time, nil), do: true

  defp newer?(time, last) do
    {:ok, last, 0} = DateTime.from_iso8601(last)
    DateTime.compare(time, last) == :gt
  end

  defp find_pending(state, id),
    do:
      Enum.find(pending(state), fn {_job, signal} ->
        Signal.get_context(signal, "jidooccurrenceid") == id
      end)

  defp payload(signal), do: signal |> Signal.to_map() |> Map.drop(@trace)
end
