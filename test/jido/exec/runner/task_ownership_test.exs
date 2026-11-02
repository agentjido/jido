defmodule Jido.Exec.Runner.TaskOwnershipTest do
  use Covenant.Case, component: "jido_action.execution", async: false
  @moduletag obligation: "jido_action.execution.I20"

  alias Jido.Exec
  alias JidoActionTest.Fixtures.Actions.KillingAction

  defmodule BlockingAction do
    use Jido.Action, name: "exec_blocking"

    @impl true
    def run(_params, %{observer: observer}) do
      Process.flag(:trap_exit, true)
      send(Process.whereis(observer), {:blocking_action_started, self()})
      wait()
    end

    defp wait do
      receive do
        {:probe, observer, token} ->
          send(observer, {:alive, token})
          wait()

        :release ->
          {:ok, %{released: true}}
      end
    end
  end

  defmodule FailingStore do
    @behaviour Runic.Runner.Store

    @impl true
    def init_store(opts), do: {:ok, Keyword.fetch!(opts, :agent)}

    @impl true
    def save(id, log, agent) do
      Agent.get_and_update(agent, fn
        %{fail?: true} = state -> {{:error, :storage_unavailable}, state}
        state -> {:ok, %{state | logs: Map.put(state.logs, id, log)}}
      end)
    end

    @impl true
    def load(id, agent) do
      Agent.get(agent, fn state ->
        case Map.fetch(state.logs, id) do
          {:ok, log} -> {:ok, log}
          :error -> {:error, :not_found}
        end
      end)
    end
  end

  setup do
    observer = :"exec_ownership_observer_#{System.unique_integer([:positive])}"
    Process.register(self(), observer)
    %{observer: observer}
  end

  test "managed execution retains an uncertain Action after a process crash" do
    runner = start_runner!()
    test_pid = self()
    execution_id = unique_id()

    assert {:ok, worker} =
             Exec.start(runner, execution_id, KillingAction, %{}, %{},
               hooks: [
                 on_failed: fn _runnable, reason, _state ->
                   send(test_pid, {:managed_failed, reason})
                 end,
                 on_idle: fn _state -> send(test_pid, :managed_idle) end
               ]
             )

    assert_receive :managed_idle, 1_000
    refute_received {:managed_failed, _reason}
    assert {:ok, workflow} = Runic.Runner.get_workflow(runner, execution_id)

    assert {:error, %Jido.Action.Error.ExecutionFailureError{details: details}} =
             Exec.result(workflow)

    assert details.outcome == :uncertain
    assert details.reason == :killed
    assert details.retry == false

    assert {:error, %Jido.Action.Error.ExecutionFailureError{details: ^details}} =
             Exec.result(runner, execution_id)

    assert Runic.Workflow.is_runnable?(workflow)
    assert is_pid(worker)
    assert Process.alive?(worker)
  end

  for timeout <- [:infinity, 60_000] do
    test "stop confirms active Action death with timeout #{inspect(timeout)}", ctx do
      runner = start_runner!()
      execution_id = unique_id()

      {_worker, action_pid} =
        start_blocked!(runner, execution_id, ctx.observer, timeout: unquote(timeout))

      monitor = Process.monitor(action_pid)

      assert :ok = Runic.Runner.stop(runner, execution_id, persist: false)
      refute Process.alive?(action_pid)
      assert_receive {:DOWN, ^monitor, :process, ^action_pid, _reason}, 1_000
    end

    test "Worker death stops active Action with timeout #{inspect(timeout)}", ctx do
      runner = start_runner!()

      {worker, action_pid} =
        start_blocked!(runner, unique_id(), ctx.observer, timeout: unquote(timeout))

      monitor = Process.monitor(action_pid)

      Process.exit(worker, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^action_pid, _reason}, 1_000
    end
  end

  test "managed execution releases finished Action tasks" do
    runner = start_runner!()
    execution_id = unique_id()
    test_pid = self()
    params = %{value: 1, amount: 2}
    hooks = [on_idle: fn _state -> send(test_pid, :managed_idle) end]

    assert {:ok, worker} =
             Exec.start(runner, execution_id, JidoActionTest.Fixtures.Actions.Add, params, %{}, hooks: hooks)

    assert_receive :managed_idle, 1_000
    assert %{executor_state: %{tasks: tasks}} = :sys.get_state(worker)
    assert tasks == %{}
  end

  test "the native executor uses the Runner supervisor and Worker group leader", ctx do
    runner = start_runner!()
    test_pid = self()
    hooks = [on_dispatch: fn _runnable, state -> send(test_pid, {:executor, state.executor}) end]
    {worker, action_pid} = start_blocked!(runner, unique_id(), ctx.observer, hooks: hooks)

    assert_receive {:executor, Runic.Runner.Executor.Task}, 1_000
    assert action_pid in Task.Supervisor.children(Module.concat(runner, TaskSupervisor))
    assert Process.info(action_pid, :group_leader) == Process.info(worker, :group_leader)
  end

  test "cancel confirms death of an active timed Action", ctx do
    runner = start_runner!()
    execution_id = unique_id()
    {worker, action_pid} = start_blocked!(runner, execution_id, ctx.observer, timeout: 60_000)
    monitor = Process.monitor(action_pid)

    assert :ok = Runic.Runner.cancel(runner, execution_id)
    refute Process.alive?(action_pid)
    refute Process.alive?(worker)
    assert_receive {:DOWN, ^monitor, :process, ^action_pid, _reason}, 1_000
  end

  test "failed persistent stop keeps the same Worker and active Action", ctx do
    store = start_supervised!({Agent, fn -> %{fail?: false, logs: %{}} end})
    runner = start_runner!(store: FailingStore, store_opts: [agent: store])
    execution_id = unique_id()
    {worker, action_pid} = start_blocked!(runner, execution_id, ctx.observer, timeout: 60_000)
    monitor = Process.monitor(action_pid)
    Agent.update(store, &%{&1 | fail?: true})

    assert {:error, {:persistence_failed, :storage_unavailable}} =
             Runic.Runner.stop(runner, execution_id)

    assert Runic.Runner.lookup(runner, execution_id) == worker
    assert Process.alive?(worker)
    token = make_ref()
    send(action_pid, {:probe, self(), token})
    assert_receive {:alive, ^token}, 1_000

    Agent.update(store, &%{&1 | fail?: false})
    assert :ok = Runic.Runner.stop(runner, execution_id)
    refute Process.alive?(action_pid)
    assert_receive {:DOWN, ^monitor, :process, ^action_pid, _reason}, 1_000
  end

  for reason <- [:normal, :kill] do
    test "managed execution outlives caller exit #{reason}", ctx do
      runner = start_runner!()
      execution_id = unique_id()
      test_pid = self()

      caller =
        start_supervised!(
          {Task,
           fn ->
             result =
               Exec.start(runner, execution_id, BlockingAction, %{}, %{observer: ctx.observer},
                 hooks: [on_idle: fn _state -> send(test_pid, :managed_idle) end]
               )

             send(test_pid, {:managed_started, result})
             receive do: (:finish -> :ok)
           end}
        )

      monitor = Process.monitor(caller)
      assert_receive {:managed_started, {:ok, worker}}, 1_000
      assert_receive {:blocking_action_started, action_pid}, 1_000

      if unquote(reason) == :normal,
        do: send(caller, :finish),
        else: Process.exit(caller, :kill)

      assert_receive {:DOWN, ^monitor, :process, ^caller, _reason}, 1_000
      assert Process.alive?(worker)
      send(action_pid, :release)
      assert_receive :managed_idle, 1_000
      assert Exec.result(runner, execution_id) == {:ok, %{released: true}}
    end
  end

  defp start_blocked!(runner, execution_id, observer, opts) do
    assert {:ok, worker} =
             Exec.start(runner, execution_id, BlockingAction, %{}, %{observer: observer}, opts)

    assert_receive {:blocking_action_started, action_pid}, 1_000
    on_exit(fn -> if Process.alive?(action_pid), do: Process.exit(action_pid, :kill) end)
    {worker, action_pid}
  end

  defp start_runner!(opts \\ []) do
    runner = :"exec_ownership_runner_#{System.unique_integer([:positive])}"
    start_supervised!({Runic.Runner, Keyword.put(opts, :name, runner)})
    runner
  end

  defp unique_id, do: {:exec_task_ownership, System.unique_integer([:positive])}
end
