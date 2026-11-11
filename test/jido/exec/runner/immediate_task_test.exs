defmodule Jido.Exec.Runner.ImmediateTaskTest do
  use Covenant.Case, component: "jido_action.execution", async: false
  @moduletag obligation: "jido_action.execution.I20"

  alias Jido.Exec
  alias Jido.Flow
  alias Jido.Flow.Ref

  defmodule BlockingAction do
    use Jido.Action, name: "exec_immediate_blocking"

    @impl true
    def run(_params, %{observer: observer}) do
      send(observer, {:action_started, self(), Process.group_leader()})

      receive do
        :release -> {:ok, %{released: true}}
      end
    end
  end

  defmodule NormalExitAction do
    use Jido.Action, name: "exec_immediate_normal_exit"

    @impl true
    def run(_params, %{observer: observer}) do
      send(observer, {:action_started, self(), Process.group_leader()})

      receive do
        :release -> Process.exit(self(), :normal)
      end
    end
  end

  defmodule KillingAction do
    use Jido.Action, name: "exec_immediate_killing"

    @impl true
    def run(_params, _context), do: Process.exit(self(), :kill)
  end

  defmodule ClassificationCrashAction do
    @behaviour Jido.Action

    def __jido_codec_kind__, do: raise("classification failed")
    def on_before_validate_params(params), do: {:ok, params}
    def validate_params(params), do: {:ok, params}
    def validate_output(output), do: {:ok, output}
    def run(params, _context), do: {:ok, params}
  end

  test "run/4 executes under the application Task Supervisor by default" do
    expected_group_leader = Process.group_leader()
    caller = run_blocking(BlockingAction, [])

    assert_receive {:action_started, action_pid, ^expected_group_leader}, 1_000
    refute action_pid == elem(caller, 0)
    refute action_pid in elem(Process.info(elem(caller, 0), :links), 1)
    assert action_pid in Task.Supervisor.children(Jido.Exec.TaskSupervisor)

    send(action_pid, :release)
    assert_caller_result(caller, {:ok, %{released: true}})
  end

  test "run/4 preserves the caller group leader" do
    group_leader = spawn(fn -> receive do: (:stop -> :ok) end)
    on_exit(fn -> if Process.alive?(group_leader), do: Process.exit(group_leader, :kill) end)
    caller = run_blocking(BlockingAction, [], group_leader)

    assert_receive {:action_started, action_pid, ^group_leader}, 1_000
    send(action_pid, :release)
    assert_caller_result(caller, {:ok, %{released: true}})

    send(group_leader, :stop)
  end

  test "an untrappable Action exit does not exit the caller" do
    assert {:error, %Jido.Error.ExecutionError{phase: :execution_task, details: details}} =
             Exec.run(KillingAction)

    assert details.reason == :killed
    assert Process.alive?(self())
  end

  test "target resolution cannot exit the caller" do
    assert {:error, %Jido.Error.ExecutionError{phase: :execution_task, details: details}} =
             Exec.run(ClassificationCrashAction)

    assert match?({{%RuntimeError{message: "classification failed"}, _stacktrace}, _call}, details.reason) or
             match?({%RuntimeError{message: "classification failed"}, _stacktrace}, details.reason)

    assert Process.alive?(self())
  end

  defmodule MapBlockingAction do
    use Jido.Action, name: "exec_immediate_map_blocking"

    @impl true
    def run(%{item: item}, %{observer: observer}) do
      send(observer, {:map_action_started, item, self()})

      receive do
        :release -> {:ok, %{item: item}}
      end
    end
  end

  test "max_concurrency is one limit across independent Maps" do
    flow =
      Flow.new!(%{
        name: "exec_immediate_global_map_limit",
        components: [
          %{
            kind: :map,
            name: "left",
            collection: [1, 2],
            action: MapBlockingAction,
            params: %{item: Ref.item()}
          },
          %{
            kind: :map,
            name: "right",
            collection: [3, 4],
            action: MapBlockingAction,
            params: %{item: Ref.item()}
          }
        ],
        output: %{left: Ref.result("left"), right: Ref.result("right")}
      })

    caller = run_blocking(flow, max_concurrency: 2)

    assert_receive {:map_action_started, _item, first}, 1_000
    assert_receive {:map_action_started, _item, second}, 1_000
    refute_received {:map_action_started, _item, _pid}

    send(first, :release)
    assert_receive {:map_action_started, _item, third}, 1_000
    send(second, :release)
    assert_receive {:map_action_started, _item, fourth}, 1_000
    send(third, :release)
    send(fourth, :release)

    assert_caller_result(caller, fn
      {:ok, %{left: left, right: right}} -> length(left) == 2 and length(right) == 2
      _result -> false
    end)
  end

  describe "caller exit" do
    test "stops an Action that runs in the execution task" do
      assert_caller_exit_stops_actions(BlockingAction, [], 1)
    end

    test "stops an Action that runs under a Runic timeout" do
      assert_caller_exit_stops_actions(BlockingAction, [timeout: 60_000], 1)
    end

    test "stops concurrent Flow Actions" do
      assert_caller_exit_stops_actions(parallel_flow(), [max_concurrency: 2], 2)
    end
  end

  test "run/4 leaves no linked helper process after completion" do
    caller = run_blocking(BlockingAction, [])

    assert_receive {:action_started, task_pid, _group_leader}, 1_000
    supervisor = GenServer.whereis(Jido.Exec.TaskSupervisor)
    {:links, links} = Process.info(task_pid, :links)
    monitors = for pid <- [task_pid | links], pid != supervisor, do: Process.monitor(pid)

    send(task_pid, :release)
    assert_caller_result(caller, {:ok, %{released: true}})

    for monitor <- monitors do
      assert_receive {:DOWN, ^monitor, :process, _pid, _reason}, 1_000
    end
  end

  test "run/4 stops its caller watcher when the execution task exits normally" do
    owner = self()

    # The caller stays alive, so only the task exit can stop the watcher.
    caller =
      spawn_link(fn ->
        result = Exec.run(NormalExitAction, %{}, %{observer: owner})
        send(owner, {:caller_result, self(), result})

        receive do
          :stop -> :ok
        end
      end)

    on_exit(fn -> send(caller, :stop) end)

    assert_receive {:action_started, task_pid, _group_leader}, 1_000
    supervisor = GenServer.whereis(Jido.Exec.TaskSupervisor)
    {:links, links} = Process.info(task_pid, :links)
    monitors = for pid <- links, pid != supervisor, pid != caller, do: Process.monitor(pid)
    assert monitors != []

    send(task_pid, :release)

    assert_receive {:caller_result, ^caller, {:error, %Jido.Error.ExecutionError{message: "Exec task exited"}}},
                   1_000

    for monitor <- monitors do
      assert_receive {:DOWN, ^monitor, :process, _pid, _reason}, 1_000
    end
  end

  test "a normal Action exit fails once under concurrent and timed execution" do
    for opts <- [[max_concurrency: 2], [timeout: 1_000]] do
      {caller, monitor} = run_blocking(parallel_normal_exit_flow(), opts)
      error = release_until_result(caller)

      assert %Jido.Error.ExecutionError{details: %{reason: :normal}} = error
      assert_receive {:DOWN, ^monitor, :process, ^caller, :normal}, 1_000
      refute_received {:action_started, _pid, _group_leader}
    end
  end

  # Releases each started Action until the caller returns its error.
  defp release_until_result(caller) do
    receive do
      {:action_started, task_pid, _group_leader} ->
        send(task_pid, :release)
        release_until_result(caller)

      {:caller_result, ^caller, {:error, error}} ->
        error
    after
      2_000 -> flunk("run/4 did not return after a normal Action exit")
    end
  end

  defp parallel_normal_exit_flow do
    Flow.new!(%{
      name: "exec_immediate_normal_exit",
      components: [
        %{kind: :step, name: "left", action: NormalExitAction, params: %{}},
        %{kind: :step, name: "right", action: NormalExitAction, params: %{}}
      ],
      output: %{left: Ref.result("left"), right: Ref.result("right")}
    })
  end

  defp assert_caller_exit_stops_actions(target, opts, count) do
    {caller, caller_monitor} = run_blocking(target, opts)

    action_monitors =
      for _index <- 1..count do
        assert_receive {:action_started, action_pid, _group_leader}, 1_000
        Process.monitor(action_pid)
      end

    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^caller_monitor, :process, ^caller, :killed}, 1_000

    for monitor <- action_monitors do
      assert_receive {:DOWN, ^monitor, :process, _pid, _reason}, 1_000
    end
  end

  defp parallel_flow do
    Flow.new!(%{
      name: "exec_immediate_parallel",
      components: [
        %{kind: :step, name: "left", action: BlockingAction, params: %{}},
        %{kind: :step, name: "right", action: BlockingAction, params: %{}}
      ],
      output: %{left: Ref.result("left"), right: Ref.result("right")}
    })
  end

  defp run_blocking(target, opts, group_leader \\ nil) do
    owner = self()

    spawn_monitor(fn ->
      if group_leader, do: Process.group_leader(self(), group_leader)
      result = Exec.run(target, %{}, %{observer: owner}, opts)
      send(owner, {:caller_result, self(), result})
    end)
  end

  defp assert_caller_result({caller, monitor}, expected) when is_function(expected, 1) do
    assert_receive {:caller_result, ^caller, result}, 1_000
    assert expected.(result)
    assert_receive {:DOWN, ^monitor, :process, ^caller, :normal}, 1_000
  end

  defp assert_caller_result({caller, monitor}, expected) do
    assert_receive {:caller_result, ^caller, ^expected}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^caller, :normal}, 1_000
  end
end
