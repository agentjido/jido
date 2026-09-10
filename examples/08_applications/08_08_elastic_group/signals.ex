defmodule Jido.Examples.Applications.ElasticGroup.Signals do
  @moduledoc "Builds the work and control Signals used by the elastic group."

  alias Jido.Signal

  @prefix "examples.applications.elastic_group"

  def work_requested(group_id, generation, target_id, task) do
    Signal.new!(
      "#{@prefix}.work.requested",
      %{
        group_id: group_id,
        generation: generation,
        target_id: target_id,
        task_id: task.id,
        attempt: task.attempt,
        value: task.value,
        delay_ms: Map.get(task, :delay_ms, 20)
      },
      source: "/examples/applications/elastic_group/controller"
    )
  end

  def worker_finish(data) do
    Signal.new!(
      "#{@prefix}.worker.finish",
      data,
      source: "/examples/applications/elastic_group/worker/clock"
    )
  end

  def drain_requested(group_id, generation, target_id) do
    Signal.new!(
      "#{@prefix}.worker.drain",
      %{group_id: group_id, generation: generation, target_id: target_id},
      source: "/examples/applications/elastic_group/controller"
    )
  end

  def environment_apply(group_id, generation, worker_id, task_id, result, attempt \\ 1) do
    Signal.new!(
      "#{@prefix}.environment.apply",
      %{
        group_id: group_id,
        generation: generation,
        worker_id: worker_id,
        task_id: task_id,
        attempt: attempt,
        result: result
      },
      source: "/examples/applications/elastic_group/worker/#{worker_id}"
    )
  end

  def work_completed(data) do
    Signal.new!(
      "#{@prefix}.work.completed",
      data,
      source: "/examples/applications/elastic_group/environment"
    )
  end

  def control(status, group_id, generation, member_id, extra \\ %{}) do
    Signal.new!(
      "#{@prefix}.control.#{status}",
      Map.merge(
        %{group_id: group_id, generation: generation, member_id: member_id},
        extra
      ),
      source: "/examples/applications/elastic_group/control"
    )
  end
end
