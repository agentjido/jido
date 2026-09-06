defmodule Jido.Topology.ControllerJobTest do
  use JidoTest.Case, async: true

  alias Jido.Examples.Topology.Cell
  alias Jido.Topology.Builder
  alias Jido.Topology.Controller.Runtime

  test "timeout retains capacity until DOWN and blocks dependents", %{jido: jido} do
    {state, task} = active_job(jido)
    ref = task.ref
    monitor = Process.monitor(task.pid)
    assert {:noreply, timed_out} = Runtime.handle_info({:task_timeout, ref}, state)
    assert map_size(timed_out.active) == 1
    assert timed_out.pending == state.pending
    assert timed_out.errors == %{}
    assert {:noreply, ^timed_out} = Runtime.handle_info({:task_timeout, ref}, timed_out)
    assert_receive {:DOWN, ^monitor, :process, _, :killed}, 1_000
    assert_receive {:DOWN, ^ref, :process, pid, :killed}, 1_000

    assert {:noreply, finished} =
             Runtime.handle_info({:DOWN, ref, :process, pid, :killed}, timed_out)

    assert finished.active == %{}

    assert finished.errors == %{
             "agent/parent" => :startup_task_timeout,
             "agent/child" => {:dependencies_unavailable, ["agent/parent"]}
           }

    assert finished.phase == :degraded
    assert_stale_messages(finished, task)
  end

  for result <- [{:ok, :late_pid}, {:error, :late_error}] do
    @result result
    test "timeout takes precedence over queued result #{inspect(result)}", %{jido: jido} do
      {state, task} = active_job(jido)
      assert {:noreply, timed_out} = Runtime.handle_info({:task_timeout, task.ref}, state)
      assert {:noreply, finished} = Runtime.handle_info({task.ref, @result}, timed_out)
      assert finished.errors["agent/parent"] == :startup_task_timeout
      assert finished.ready == %{}
      assert finished.active == %{}
      assert_stale_messages(finished, task)
    end
  end

  test "result releases a slot once and later timeout and DOWN are stale", %{jido: jido} do
    {state, task} = active_job(jido)
    state = %{state | pending: MapSet.new()}
    assert {:noreply, finished} = Runtime.handle_info({task.ref, {:ok, self()}}, state)
    assert finished.ready == %{"agent/parent" => self()}
    assert finished.errors == %{}
    assert finished.active == %{}
    assert finished.phase == :ready
    assert_stale_messages(finished, task)
  end

  test "DOWN without timeout keeps its reason", %{jido: jido} do
    {state, task} = active_job(jido)

    assert {:noreply, finished} =
             Runtime.handle_info({:DOWN, task.ref, :process, task.pid, :activation_failed}, state)

    assert finished.errors["agent/parent"] == :activation_failed
    assert finished.active == %{}
    assert_stale_messages(finished, task)
  end

  test "unknown references do not change an active job", %{jido: jido} do
    {state, _task} = active_job(jido)
    unknown = make_ref()
    assert {:noreply, ^state} = Runtime.handle_info({unknown, {:ok, self()}}, state)
    assert {:noreply, ^state} = Runtime.handle_info({:task_timeout, unknown}, state)
    assert {:noreply, ^state} = Runtime.handle_info({:reconcile, unknown}, state)

    assert {:noreply, ^state} =
             Runtime.handle_info({:DOWN, unknown, :process, self(), :normal}, state)
  end

  defp active_job(jido) do
    supervisor = start_supervised!(Task.Supervisor)
    observer = self()

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        send(observer, {:task_waiting, self()})

        receive do
          :release -> {:ok, self()}
        end
      end)

    assert_receive {:task_waiting, pid}, 1_000
    assert pid == task.pid
    timer = Process.send_after(self(), {:task_timeout, task.ref}, 60_000)
    on_exit(fn -> Process.cancel_timer(timer) end)

    instance =
      Builder.new(name: "job-events")
      |> Builder.agent(:parent, Cell)
      |> Builder.agent(:child, Cell)
      |> Builder.owns(:parent, :child)
      |> Builder.startup(concurrency: 1, retry_interval: 60_000)
      |> Builder.build!(id: "job-events")

    state = %{
      jido: jido,
      instance: instance,
      repair: :manual,
      reconcile_requested: false,
      reconcile_timer: nil,
      reconcile_token: nil,
      ready: %{},
      errors: %{},
      waiters: %{},
      phase: :starting,
      pending: MapSet.new(["agent/child"]),
      active: %{task.ref => %{key: "agent/parent", task: task, timer: timer, timed_out?: false}}
    }

    {state, task}
  end

  defp assert_stale_messages(state, task) do
    assert {:noreply, ^state} = Runtime.handle_info({task.ref, {:ok, self()}}, state)
    assert {:noreply, ^state} = Runtime.handle_info({:task_timeout, task.ref}, state)

    assert {:noreply, ^state} =
             Runtime.handle_info({:DOWN, task.ref, :process, task.pid, :normal}, state)
  end
end
