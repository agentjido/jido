defmodule Jido.Examples.Factory.Inspection do
  @moduledoc "Read-only factory views from a serialized Agent turn."
  use Jido.Action,
    name: "factory_inspection",
    schema:
      Zoi.object(%{
        view: Zoi.enum([:job, :events]),
        job_id: Zoi.string() |> Zoi.default("")
      })

  def run(%{view: :job, job_id: id}, %{agent_state: state}) do
    if Map.has_key?(state.jobs, id),
      do: {:ok, state},
      else: Jido.Examples.Factory.Protocol.invalid("Job was not found")
  end

  def run(%{view: :events}, %{agent_state: state}), do: {:ok, state}

  @doc "Returns jobs, capacity, queue order, and scheduler activity."
  def overview(state) do
    counts =
      Map.merge(
        Map.new([:queued, :running, :paused, :completed, :cancelled, :failed], &{&1, 0}),
        Enum.frequencies_by(Map.values(state.jobs), & &1.status)
      )

    Map.merge(%{jobs: state.jobs, counts: counts, max_concurrent_jobs: 1}, runtime_view(state))
  end

  defp runtime_view(%{queue: queue} = state) do
    %{
      kind: :workshop,
      queued_job_ids: queue,
      active_job_id: state.active_job_id,
      active_worker_id:
        if(state.active_job_id == "", do: "", else: state.jobs[state.active_job_id].worker_id),
      scheduler: %{
        enabled: Map.has_key?(state.scheduler.cron, "factory_poll"),
        interval_ms: 1_000,
        checks: state.poll_count
      }
    }
  end

  defp runtime_view(state) do
    %{
      kind: :departments,
      ready: state.ready,
      active_steps: state.active,
      max_concurrent_steps: 2
    }
  end

  @doc "Returns one job with its queue position, or the recent event history."
  def view(state, :job, id) do
    position = Enum.find_index(Map.get(state, :queue, []), &(&1 == id))
    %{job: Map.fetch!(state.jobs, id), queue_position: if(position, do: position + 1, else: nil)}
  end

  def view(state, :events, ""), do: %{events: state.events}
  def view(state, :events, id), do: %{events: Enum.filter(state.events, &(&1.job_id == id))}
end
