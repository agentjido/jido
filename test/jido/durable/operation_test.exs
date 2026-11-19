defmodule Jido.Durable.OperationTest do
  use Covenant.Case, component: "jido.durable", async: false

  alias Jido.Durable
  alias Jido.Durable.{Ref, Status}
  alias Jido.Instance.{Names, RuntimeStore}
  alias Jido.Persistence.ContinuationStore
  alias Jido.Persistence.Store
  alias Runic.Runner

  defmodule Gate do
    use Jido.Action, name: "durable_operation_gate"

    @impl true
    def run(%{step: step} = params, _context) do
      Process.flag(:trap_exit, true)
      send(Jido.Durable.OperationTest, {:gate, step, self()})

      receive do
        :release -> {:ok, params}
      end
    end
  end

  defmodule GatedFlow do
    use Jido.Flow, name: "durable_operation_flow"

    flow do
      step "first", action: Gate, params: %{step: 1}
      step "second", action: Gate, params: %{step: 2, before: result("first")}
      output result("second")
    end
  end

  defmodule MixedFlow do
    use Jido.Flow, name: "durable_pending_timer_and_action"

    flow do
      await "permission", event: "durable.release"
      timer "future", after_ms: 60_000
      step "gate", action: Gate, params: %{step: 1, permission: result("permission")}
      output %{gate: result("gate"), timer: result("future")}
    end
  end

  setup do
    Process.register(self(), __MODULE__)
    name = :"jido_durable_operation_#{System.unique_integer([:positive])}"
    persistence = {Jido.Persistence.ETS, table: Module.concat(__MODULE__, Store)}
    start_supervised!({Jido, name: name, namespace: "durable/#{name}", persistence: persistence})
    %{jido: name, runner: Names.exec_runner(name)}
  end

  @tag obligation: "jido.durable.I1"
  test "competing start, resume, and Signal calls leave the live operation alone", c do
    input = signal("durable.start")
    approval = signal("durable.release")
    {ref, wait_id} = open_waits(c.jido, input)

    active = Task.async(fn -> Durable.signal(c.jido, ref, wait_id, approval, now: 101) end)
    assert_receive {:gate, 1, action}, 2_000

    assert {:error, :execution_busy} = Durable.start(c.jido, MixedFlow, input, now: 101, operation_timeout: 20)
    assert {:error, :execution_busy} = Durable.resume(c.jido, ref, now: 101, operation_timeout: 20)
    assert {:error, :execution_busy} = Durable.signal(c.jido, ref, wait_id, approval, now: 101, operation_timeout: 20)
    assert {:ok, %Status{state: :waiting}} = Durable.start(c.jido, MixedFlow, signal("durable.other"), now: 101)
    refute_received {:gate, _, _}

    send(action, :release)
    assert {:ok, %Status{state: :waiting}} = Task.await(active)
  end

  @tag obligation: "jido.durable.I1"
  test "another caller can resume after the operation owner dies", c do
    input = signal("durable.start")
    {:ok, ref} = Durable.ref(c.jido, input.id)

    {owner, owner_ref} = spawn_monitor(fn -> Durable.start(c.jido, GatedFlow, input) end)
    assert_receive {:gate, 1, old_action}, 2_000
    monitor = Process.monitor(old_action)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^owner_ref, :process, ^owner, :killed}, 2_000
    assert_receive {:DOWN, ^monitor, :process, ^old_action, _reason}, 2_000

    resumed = Task.async(fn -> Durable.resume(c.jido, ref) end)
    assert_receive {:gate, 1, new_action}, 2_000
    send(new_action, :release)
    assert_receive {:gate, 2, second}, 2_000
    send(second, :release)
    assert {:ok, %Status{state: :completed}} = Task.await(resumed)
  end

  @tag obligation: "jido.durable.I2"
  test "progress uses one deadline and timeout stops work before another caller resumes", c do
    input = signal("durable.start")
    {:ok, ref} = Durable.ref(c.jido, input.id)
    first_run = Task.async(fn -> Durable.start(c.jido, GatedFlow, input, operation_timeout: 1_000) end)

    assert_receive {:gate, 1, first}, 2_000
    Process.send_after(first, :release, 625)
    assert_receive {:gate, 2, second}, 2_000
    second_monitor = Process.monitor(second)
    Process.send_after(second, :release, 625)

    assert {:error, %{details: %{reason: :timeout, retry: true}}} = Task.await(first_run)
    refute Process.alive?(second)
    assert_receive {:DOWN, ^second_monitor, :process, ^second, _reason}, 2_000
    refute Runner.lookup(c.runner, Ref.execution_id(ref))
    assert {:ok, %Status{state: :ready}} = Durable.status(c.jido, ref)

    resumed = Task.async(fn -> Durable.resume(c.jido, ref) end)
    assert_receive {:gate, 2, next}, 2_000
    refute_received {:gate, 1, _}
    send(next, :release)

    assert {:ok, %Status{state: :completed}} = Task.await(resumed)
    assert {:ok, %{step: 2, before: %{step: 1}}} = Durable.result(c.jido, ref)
  end

  @tag obligation: "jido.durable.I2"
  test "timeout does not leave progress messages in a live caller's mailbox", c do
    input = signal("durable.start")
    owner = self()

    caller =
      Task.async(fn ->
        result = Durable.start(c.jido, GatedFlow, input, operation_timeout: 300)
        send(owner, {:timed_out, result})

        receive do
          :inspect -> Process.info(self(), :messages)
        end
      end)

    assert_receive {:gate, 1, action}, 2_000
    assert_receive {:timed_out, {:error, %{details: %{reason: :timeout}}}}, 2_000
    refute Process.alive?(action)
    send(caller.pid, :inspect)
    assert {:messages, []} = Task.await(caller)
  end

  @tag obligation: "jido.durable.I2"
  test "an expired operation starts no work", c do
    input = signal("durable.start")
    assert {:error, %{details: %{reason: :timeout}}} = Durable.start(c.jido, GatedFlow, input, operation_timeout: 0)
    assert {:ok, ref} = Durable.ref(c.jido, input.id)
    assert {:error, :not_found} = Durable.status(c.jido, ref)
    refute_received {:gate, _, _}
  end

  @tag obligation: "jido.durable.I3"
  test "a checkpoint reports ready work and retains the independent timer", c do
    {ref, wait_id} = open_waits(c.jido, signal("durable.start"))
    input = signal("durable.release")

    {owner, owner_ref} = spawn_monitor(fn -> Durable.signal(c.jido, ref, wait_id, input, now: 101) end)
    assert_receive {:gate, 1, action}, 2_000
    action_ref = Process.monitor(action)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^owner_ref, :process, ^owner, :killed}, 2_000
    assert_receive {:DOWN, ^action_ref, :process, ^action, _reason}, 2_000

    assert {:ok, %Status{state: :ready, waits: [timer], next_wake_at: 60_100}} =
             Durable.status(c.jido, ref)

    resumed = Task.async(fn -> Durable.resume(c.jido, ref, now: 102) end)
    assert_receive {:gate, 1, next}, 2_000
    send(next, :release)
    assert {:ok, %Status{state: :waiting, waits: [^timer], next_wake_at: 60_100}} = Task.await(resumed)
  end

  @tag obligation: "jido.durable.I4"
  test "status and result leave the continuation registration and stream intact", c do
    input = signal("durable.start")
    {:ok, ref} = Durable.ref(c.jido, input.id)
    id = Ref.execution_id(ref)
    active = Task.async(fn -> Durable.start(c.jido, GatedFlow, input) end)

    assert_receive {:gate, 1, first}, 2_000
    assert {:ok, registration} = RuntimeStore.fetch(c.jido, ContinuationStore, id)
    assert {:ok, events} = ContinuationStore.stream(id, c.jido)

    reader = Task.async(fn -> {Durable.status(c.jido, ref), Durable.result(c.jido, ref)} end)
    assert {{:ok, %Status{state: :running}}, {:error, %Jido.Error.ExecutionError{}}} = Task.await(reader)
    assert RuntimeStore.fetch(c.jido, ContinuationStore, id) == {:ok, registration}
    assert ContinuationStore.stream(id, c.jido) == {:ok, events}

    send(first, :release)
    assert_receive {:gate, 2, second}, 2_000
    send(second, :release)
    assert {:ok, %Status{state: :completed}} = Task.await(active)
    assert {:ok, %{step: 2}} = Durable.result(c.jido, ref)
  end

  @tag obligation: "jido.durable.I4"
  test "status and result return the same missing-reference error", c do
    {:ok, ref} = Durable.ref(c.jido, "missing")
    assert {:error, :not_found} = Durable.status(c.jido, ref)
    assert {:error, :not_found} = Durable.result(c.jido, ref)
  end

  @tag obligation: "jido.durable.I4"
  test "reads committed batches beyond a missing count without repairing it", c do
    {ref, _wait_id} = open_waits(c.jido, signal("durable.start"))
    id = Ref.execution_id(ref)
    count_key = "jido:execution:v3:" <> Base.url_encode64(:erlang.term_to_binary(id), padding: false)
    assert {:ok, profile} = Jido.Persistence.resolve_config(:inherit, c.jido)
    assert {:ok, _bytes, _condition} = Store.read(profile.store, count_key)
    assert :ok = Store.delete(profile.store, count_key)

    assert {:ok, %Status{state: :waiting, waits: [_, _], next_wake_at: 60_100}} = Durable.status(c.jido, ref)
    assert {:error, %Jido.Error.ExecutionError{}} = Durable.result(c.jido, ref)
    assert {:error, :not_found} = Store.read(profile.store, count_key)

    assert {:ok, %Status{state: :waiting}} = Durable.resume(c.jido, ref, now: 101)
    assert {:ok, _bytes, _condition} = Store.read(profile.store, count_key)
  end

  defp open_waits(jido, input) do
    assert {:ok, %Status{state: :waiting, ref: ref, waits: waits, next_wake_at: 60_100}} =
             Durable.start(jido, MixedFlow, input, now: 100)

    assert %{id: wait_id} = Enum.find(waits, &(&1.path == ["permission"]))
    {ref, wait_id}
  end

  defp signal(type), do: Jido.Signal.new!(type, %{}, source: "/durable-test")
end
