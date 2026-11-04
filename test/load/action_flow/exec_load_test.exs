defmodule JidoTest.Load.ActionFlow.ExecLoadTest do
  use ExUnit.Case, async: false

  @moduletag :load
  @moduletag timeout: 60_000

  alias Jido.Exec

  defmodule IsolatedWork do
    use Jido.Action, name: "load_isolated_work"

    @impl true
    def run(%{id: id, value: value}, %{observer: observer, run_ref: run_ref}) do
      send(observer, {run_ref, :execution, id, self()})
      {:ok, %{id: id, value: value + 1}}
    end
  end

  defmodule IsolatedFlow do
    use Jido.Flow, name: "load_isolated_flow"

    alias JidoTest.Load.ActionFlow.ExecLoadTest.IsolatedWork

    flow do
      step "work",
        action: IsolatedWork,
        params: %{id: input(:id), value: input(:value)}

      output %{id: result("work", :id), value: result("work", :value)}
    end
  end

  test "200 concurrent workflows keep their own inputs and release every process" do
    baseline = task_children()
    observer = self()
    run_ref = make_ref()

    results =
      1..200
      |> Task.async_stream(
        fn value ->
          result =
            Exec.run(
              IsolatedFlow,
              %{id: value, value: value},
              %{observer: observer, run_ref: run_ref}
            )

          {self(), value, result}
        end,
        max_concurrency: System.schedulers_online(),
        ordered: true,
        timeout: 10_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.map(results, fn {_pid, value, result} -> {value, result} end) ==
             Enum.map(1..200, &{&1, {:ok, %{id: &1, value: &1 + 1}}})

    caller_tasks = Enum.map(results, &elem(&1, 0))

    execution_tasks =
      for id <- 1..200 do
        assert_receive {^run_ref, :execution, ^id, pid}, 5_000
        pid
      end

    assert MapSet.size(MapSet.new(caller_tasks)) == 200
    assert MapSet.size(MapSet.new(execution_tasks)) == 200
    assert Enum.all?(caller_tasks, &(not Process.alive?(&1)))
    assert Enum.all?(execution_tasks, &(not Process.alive?(&1)))
    assert_task_children_return_to(baseline)
  end

  defp assert_task_children_return_to(expected, attempts \\ 50)
  defp assert_task_children_return_to(expected, 0), do: assert(task_children() == expected)

  defp assert_task_children_return_to(expected, attempts) do
    if task_children() == expected do
      :ok
    else
      Process.sleep(10)
      assert_task_children_return_to(expected, attempts - 1)
    end
  end

  defp task_children do
    Jido.Exec.TaskSupervisor
    |> Task.Supervisor.children()
    |> MapSet.new()
  end
end
