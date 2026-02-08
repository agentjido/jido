defmodule JidoTest.Runtime.TaskingTest do
  use ExUnit.Case, async: true

  alias Jido.Runtime.Tasking

  describe "resolve_task_supervisor/1" do
    test "returns first alive supervisor from candidates" do
      missing = :"missing_task_sup_#{System.unique_integer([:positive])}"
      available = :"available_task_sup_#{System.unique_integer([:positive])}"

      {:ok, _pid} =
        start_supervised({Task.Supervisor, name: available},
          id: {:task_supervisor, available}
        )

      assert {:ok, ^available} = Tasking.resolve_task_supervisor(candidates: [missing, available])
    end

    test "returns error when no candidates are alive" do
      missing = :"missing_task_sup_#{System.unique_integer([:positive])}"

      assert {:error, :task_supervisor_not_found} =
               Tasking.resolve_task_supervisor(candidates: [missing])
    end
  end

  describe "start_child/2" do
    test "starts a task under resolved supervisor" do
      supervisor = :"tasking_start_child_sup_#{System.unique_integer([:positive])}"

      {:ok, _pid} =
        start_supervised({Task.Supervisor, name: supervisor},
          id: {:task_supervisor, supervisor}
        )

      parent = self()

      assert {:ok, task_pid} =
               Tasking.start_child(
                 fn ->
                   send(parent, :task_executed)
                 end,
                 candidates: [supervisor]
               )

      assert is_pid(task_pid)
      assert_receive :task_executed
    end

    test "returns not_found when no task supervisor can be resolved" do
      missing = :"missing_task_sup_#{System.unique_integer([:positive])}"

      assert {:error, :task_supervisor_not_found} =
               Tasking.start_child(fn -> :ok end, candidates: [missing])
    end
  end
end
