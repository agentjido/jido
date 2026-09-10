defmodule Jido.Examples.Applications.FixedGroup.Signals do
  @moduledoc "Builds the Bus Signals used by the fixed group roles."

  alias Jido.Signal

  @prefix "examples.applications.fixed_group"

  def work_requested(group_id, generation, target_id, task) do
    Signal.new!(
      "#{@prefix}.work.requested",
      %{
        group_id: group_id,
        generation: generation,
        target_id: target_id,
        task_id: task.id,
        value: task.value
      },
      source: "/examples/applications/fixed_group/controller"
    )
  end

  def environment_apply(group_id, generation, worker_id, task_id, result) do
    Signal.new!(
      "#{@prefix}.environment.apply",
      %{
        group_id: group_id,
        generation: generation,
        worker_id: worker_id,
        task_id: task_id,
        result: result
      },
      source: "/examples/applications/fixed_group/worker/#{worker_id}"
    )
  end

  def work_applied(data) do
    Signal.new!(
      "#{@prefix}.work.applied",
      data,
      source: "/examples/applications/fixed_group/environment"
    )
  end

  def member_ready(group_id, generation, member_id, role, restarted?) do
    Signal.new!(
      "#{@prefix}.control.member.ready",
      %{
        group_id: group_id,
        generation: generation,
        member_id: member_id,
        role: role,
        restarted: restarted?
      },
      source: "/examples/applications/fixed_group/controller"
    )
  end
end
