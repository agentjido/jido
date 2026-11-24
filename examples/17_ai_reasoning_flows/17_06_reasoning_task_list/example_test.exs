Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("support/plan_client.ex", __DIR__)
Code.require_file("task_list.ex", __DIR__)
Code.require_file("plan.ex", __DIR__)
Code.require_file("work.ex", __DIR__)
Code.require_file("example.ex", __DIR__)

defmodule Jido.Examples.AI.Reasoning.TaskListTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.AI.Reasoning.TaskList.{Agent, PlanClient}

  setup do
    suffix = System.unique_integer([:positive])
    instance = :"reasoning_task_list_#{suffix}"
    start_supervised!({Jido, name: instance}, id: instance)

    agent =
      Agent.instantiate!(
        id: "release-review-#{suffix}",
        state: %{
          release: %{
            changes: ["Add an export", "Fix empty reports"],
            checks_passed: 12,
            checks_failed: 2,
            release_notes_present: false
          }
        }
      )

    {:ok, server} = Jido.start_agent(instance, agent)
    :ok = AgentServer.await_ready(server)
    %{server: server, instance: instance}
  end

  test "the planning and work Flows commit progress and results in task order", %{server: server, instance: instance} do
    assert {:ok, %{status: :committed, reply: %{type: "jido.ai.response", data: plan}}} =
             plan(server, "Review the release.")

    assert %{completed: 0, total: 3, tasks: tasks} = plan
    assert Enum.map(tasks, & &1.id) == ["changes", "checks", "release_notes"]
    assert Enum.all?(tasks, &match?(%{status: :pending, result: nil}, &1))

    assert %{completed: 0, tasks: [%{status: :in_progress, result: nil} | _]} = advance(server)

    assert %{completed: 1, total: 3, tasks: [first, second, third]} = advance(server)
    assert %{status: :completed, result: "Add an export, Fix empty reports"} = first
    assert %{status: :in_progress, result: nil} = second
    assert %{status: :pending, result: nil} = third

    assert %{completed: 2, tasks: [^first, second, %{status: :in_progress}]} = advance(server)
    assert %{status: :completed, result: "12 passed, 2 failed."} = second

    assert %{completed: 3, tasks: [^first, ^second, third]} = complete = advance(server)
    assert %{status: :completed, result: "Release notes are missing."} = third
    assert advance(server) == complete
    assert AgentServer.snapshot(server).agent.state.tasks == complete.tasks

    monitor = Process.monitor(server)
    assert :ok = Jido.stop_agent(instance, server)
    assert_receive {:DOWN, ^monitor, :process, ^server, _}
  end

  test "invalid model plans leave the current list and its progress intact", %{server: server} do
    assert {:ok, %{status: :committed, reply: %{data: %{total: 1, tasks: [%{id: "checks"}]}}}} =
             plan(server, "Report the verification results.")

    assert %{completed: 0, tasks: [%{status: :in_progress}]} = advance(server)
    before = AgentServer.snapshot(server)

    for brief <- ["Return an unknown task.", "Return duplicate tasks."] do
      assert {:ok, %{status: :failed, error: %Jido.Error.ExecutionError{}}} = plan(server, brief)
      assert AgentServer.snapshot(server) == before
    end

    assert %{completed: 1, total: 1, tasks: [%{status: :completed, result: "12 passed, 2 failed."}]} =
             advance(server)

    assert {:ok, %{status: :committed, reply: %{data: %{completed: 0, total: 3, tasks: tasks}}}} =
             plan(server, "Review the release.")

    assert Enum.all?(tasks, &match?(%{status: :pending, result: nil}, &1))
  end

  defp plan(server, brief) do
    signal = Agent.request_signal!(%{input: brief})
    AgentServer.call(server, signal, context: %{jido_ai_inference_client: PlanClient})
  end

  defp advance(server) do
    signal = Agent.advance_signal!(%{})

    assert {:ok, %{status: :committed, reply: %{type: "examples.ai.reasoning.task_list.progress", data: progress}}} =
             AgentServer.call(server, signal)

    progress
  end
end
