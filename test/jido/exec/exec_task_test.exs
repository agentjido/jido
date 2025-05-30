defmodule Jido.ExecTaskTest do
  use JidoTest.Case, async: false

  # Import Private to access private functions for testing
  use Private
  alias JidoTest.TestActions.SpawnerAction
  alias JidoTest.TestActions.TaskAction
  alias Jido.Exec
  @moduletag :capture_log
  describe "spawning multiple processes" do
    test "handles action spawning multiple processes" do
      result = Exec.execute_action_with_timeout(SpawnerAction, %{count: 10}, %{}, 1000)
      assert {:ok, %{result: "Multi-process action completed"}} = result
      # Ensure no lingering processes
      :timer.sleep(150)
      process_list = Process.list()
      process_count = length(process_list)
      assert process_count <= :erlang.system_info(:process_count)
    end

    test "handles naked task action spawning multiple processes" do
      result =
        Exec.execute_action_with_timeout(
          NakedTaskAction,
          %{count: 2},
          %{},
          # Short timeout to force error
          100
        )

      assert {:error, error} = result
      assert error.type == :execution_error
    end

    test "properly cleans up linked tasks when task group is terminated" do
      initial_count = length(Process.list())

      # Start a long-running task that will be linked to the task group
      result =
        Exec.execute_action_with_timeout(
          TaskAction,
          # Long delay to ensure task is still running
          %{count: 1, delay: 5000},
          %{},
          # Short timeout to force termination
          100
        )

      # Should timeout
      assert {:error, _} = result

      # Wait briefly for cleanup
      :timer.sleep(150)

      # Verify no lingering processes
      final_count = length(Process.list())
      assert_in_delta final_count, initial_count, 2
    end

    test "cleans up multiple linked tasks on task group termination" do
      initial_count = length(Process.list())

      # Start multiple long-running tasks linked to task group
      result =
        Exec.execute_action_with_timeout(
          TaskAction,
          # Long delay
          %{count: 5, delay: 5000},
          %{},
          # Short timeout
          100
        )

      assert {:error, _} = result

      # Wait briefly for cleanup
      :timer.sleep(150)

      # Verify all tasks were cleaned up
      final_count = length(Process.list())
      assert_in_delta final_count, initial_count, 2
    end
  end

  describe "cleanup_task_group/1" do
    test "kills the task group and all its child processes" do
      # Create a task group that will stay alive until we kill it
      {:ok, task_group} =
        Task.Supervisor.start_child(
          Jido.TaskSupervisor,
          fn ->
            Process.flag(:trap_exit, true)

            receive do
              {:shutdown} -> :ok
            end
          end
        )

      # Create some child processes under the task group
      child_pids =
        for _ <- 1..3 do
          {:ok, pid} =
            Task.Supervisor.start_child(
              Jido.TaskSupervisor,
              fn ->
                Process.group_leader(self(), task_group)
                # Keep process alive until killed
                Process.sleep(:infinity)
              end
            )

          pid
        end

      # Verify task group and children are alive
      assert Process.alive?(task_group)
      assert Enum.all?(child_pids, &Process.alive?/1)

      # Call cleanup_task_group
      Exec.cleanup_task_group(task_group)

      # Give processes time to be killed
      Process.sleep(200)

      # Verify task group and all children are dead
      refute Process.alive?(task_group)
      assert Enum.all?(child_pids, fn pid -> not Process.alive?(pid) end)
    end

    test "handles already dead task group" do
      # Create and immediately kill a task group
      {:ok, task_group} =
        Task.Supervisor.start_child(
          Jido.TaskSupervisor,
          fn ->
            Process.flag(:trap_exit, true)

            receive do
              {:shutdown} -> :ok
            end
          end
        )

      Process.exit(task_group, :kill)
      Process.sleep(100)

      # Should not raise when cleaning up already dead task group
      Exec.cleanup_task_group(task_group)
    end

    test "kills only processes in the task group" do
      # Create a task group
      {:ok, task_group} =
        Task.Supervisor.start_child(
          Jido.TaskSupervisor,
          fn ->
            Process.flag(:trap_exit, true)

            receive do
              {:shutdown} -> :ok
            end
          end
        )

      # Create a process in the task group
      {:ok, group_pid} =
        Task.Supervisor.start_child(
          Jido.TaskSupervisor,
          fn ->
            Process.group_leader(self(), task_group)
            Process.sleep(:infinity)
          end
        )

      # Create a process outside the task group
      {:ok, other_pid} =
        Task.Supervisor.start_child(
          Jido.TaskSupervisor,
          fn ->
            Process.sleep(:infinity)
          end
        )

      # Verify both processes are alive
      assert Process.alive?(group_pid)
      assert Process.alive?(other_pid)

      # Call cleanup_task_group
      Exec.cleanup_task_group(task_group)

      Process.sleep(200)

      # Verify only task group process was killed
      refute Process.alive?(group_pid)
      assert Process.alive?(other_pid)

      # Cleanup
      Process.exit(other_pid, :kill)
    end
  end
end
