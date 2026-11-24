Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("support/plan_client.ex", __DIR__)
Code.require_file("task_list.ex", __DIR__)
Code.require_file("plan.ex", __DIR__)
Code.require_file("work.ex", __DIR__)
Code.require_file("example.ex", __DIR__)

alias Jido.Agent.Directive.Reply
alias Jido.Examples.AI.Reasoning.TaskList.{Agent, PlanClient}

show_progress = fn %{completed: completed, total: total, tasks: tasks} ->
  IO.puts("\n#{completed} of #{total} completed")

  for task <- tasks do
    result = if task.result, do: " | #{task.result}", else: ""
    IO.puts("  [#{task.status}] #{task.title}#{result}")
  end
end

agent =
  Agent.instantiate!(
    id: "release-review-demo",
    state: %{
      release: %{
        changes: ["Add an export", "Fix empty reports"],
        checks_passed: 12,
        checks_failed: 2,
        release_notes_present: false
      }
    }
  )

{:ok, agent, [%Reply{signal: %{data: plan}}]} =
  Agent.cmd(agent, Agent.request_signal!(%{input: "Review the release."}),
    context: %{jido_ai_inference_client: PlanClient}
  )

show_progress.(plan)

{_agent, %{completed: completed, total: completed}} =
  Enum.reduce(1..(plan.total + 1), {agent, plan}, fn _, {agent, _progress} ->
    {:ok, next, [%Reply{signal: %{data: progress}}]} = Agent.cmd(agent, Agent.advance_signal!(%{}))
    show_progress.(progress)
    {next, progress}
  end)
