defmodule Jido.Exec.Perf.LoadTest do
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

    alias Jido.Exec.Perf.LoadTest.IsolatedWork

    flow do
      step "work",
        action: IsolatedWork,
        params: %{id: input(:id), value: input(:value)}

      output %{id: result("work", :id), value: result("work", :value)}
    end
  end

  defmodule IterateWork do
    use Jido.Action, name: "load_iterate_work"

    @impl true
    def run(%{id: id, count: index, index: index, stage: :prepare}, %{run_id: id}) do
      {:ok, %{id: id, index: index}, [{id, index, :prepare}]}
    end

    def run(%{id: id, index: index, stage: :commit}, %{run_id: id}) do
      {:ok, %{id: id, count: index + 1}, [{id, index, :commit}]}
    end
  end

  defmodule IterateChild do
    use Jido.Flow, name: "load_iterate_child"

    flow do
      step "prepare",
        action: IterateWork,
        params: %{id: input(:id), count: input(:count), index: input(:index), stage: :prepare}

      step "commit",
        action: IterateWork,
        params: %{id: result("prepare", :id), index: result("prepare", :index), stage: :commit}

      output result("commit")
    end
  end

  defmodule IterateParent do
    use Jido.Flow, name: "load_iterate_parent"

    flow do
      iterate "loop" do
        state Jido.Joi.map(), initial: %{id: input(:id), count: 0}
        flow IterateChild
        params %{id: state(:id), count: state(:count), index: iteration_index()}
        while state(:count) < input(:iterations)
        max_iterations 10_000
      end

      output result("loop")
    end
  end

  test "a Flow body reaches the 10,000-iteration limit with every effect in order" do
    baseline = task_children()
    assert_iterate_result(1, 10_000, run_iterate(1, 10_000))
    assert_task_children_return_to(baseline)
  end

  test "200 callers keep Flow body state, run context, and effects isolated" do
    baseline = task_children()
    iterations = 50

    1..200
    |> Task.async_stream(
      fn id -> {id, run_iterate(id, iterations)} end,
      max_concurrency: System.schedulers_online(),
      ordered: false,
      timeout: 30_000
    )
    |> Enum.each(fn {:ok, {id, result}} -> assert_iterate_result(id, iterations, result) end)

    assert_task_children_return_to(baseline)
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

  defp run_iterate(id, iterations) do
    Exec.run(IterateParent, %{id: id, iterations: iterations}, %{run_id: id})
  end

  defp assert_iterate_result(id, iterations, result) do
    expected = %{id: id, count: iterations}

    assert {:ok, %{iterations: ^iterations, state: ^expected, output: ^expected}, effects} = result

    expected_effects =
      for index <- 0..(iterations - 1), stage <- [:prepare, :commit] do
        {id, index, stage}
      end

    assert effects == expected_effects
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
