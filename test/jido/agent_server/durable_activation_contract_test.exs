defmodule Jido.AgentServer.DurableActivationContractTest do
  use Covenant.Case, component: "jido.agent_server", async: false

  alias Jido.Agent.Address
  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.{Snapshot, Status, TurnResult}
  alias Runic.Identity.CanonicalError

  defmodule Add do
    use Jido.Action,
      name: "durable_activation_add",
      schema: Jido.Joi.object(%{by: Jido.Joi.integer()})

    @impl true
    def run(%{by: by}, context) do
      {:ok, %{context.agent_state | count: context.agent_state.count + by}}
    end
  end

  defmodule Fail do
    use Jido.Action,
      name: "durable_activation_fail",
      schema: Jido.Joi.object(%{})

    @impl true
    def run(_params, _context), do: {:error, :expected_failure}
  end

  defmodule LargeValue do
    use Jido.Action, name: "durable_activation_large_value"

    @impl true
    def run(%{bytes: bytes}, _context), do: {:ok, %{value: :binary.copy(<<0>>, bytes)}}
  end

  defmodule LargeStep do
    use Jido.Flow, name: "durable_activation_large_step"

    flow do
      step "large", action: LargeValue, params: %{bytes: 17_000_000}
      output result("large")
    end
  end

  defmodule LargeJoin do
    use Jido.Flow, name: "durable_activation_large_join"

    flow do
      step "left", action: LargeValue, params: %{bytes: 9_000_000}
      step "right", action: LargeValue, params: %{bytes: 9_000_000}

      step "combine", [left <- result("left", :value), right <- result("right", :value)] do
        {:ok, %{count: byte_size(left) + byte_size(right)}}
      end

      output result("combine")
    end
  end

  defmodule Approval do
    use Jido.Flow,
      name: "durable_activation_approval",
      schema: Jido.Joi.object(%{request_id: Jido.Joi.string()})

    flow do
      selection "decision" do
        await "approved",
          event: "counter.approved",
          match: %{request_id: input(:request_id)}

        timer "expired", after_ms: 3_600_000
      end

      step "finish", _decision <- result("decision"), inline: [context: context] do
        {:ok, %{count: context.agent_state.count + 1}}
      end

      output result("finish")
    end
  end

  defmodule DelayedIncrement do
    use Jido.Flow, name: "durable_activation_delayed_increment"

    flow do
      timer "delay", after_ms: 300

      step "finish", _timer <- result("delay"), inline: [context: context] do
        {:ok, %{count: context.agent_state.count + 10}}
      end

      output result("finish")
    end
  end

  defmodule Upgrade do
    use Jido.Action, name: "durable_activation_upgrade"

    @impl true
    def run(%{snapshot: snapshot}, _context) do
      agent = %{
        snapshot.agent
        | vsn: snapshot.agent.vsn + 1,
          state: %{snapshot.agent.state | count: snapshot.agent.state.count + 100}
      }

      with {:ok, next} <- Jido.Persistence.snapshot(agent),
           do: {:ok, %{snapshot: next}}
    end
  end

  defmodule StablePluginRuntime do
    use GenServer

    def start_link(init), do: GenServer.start_link(__MODULE__, init)
    def status(pid), do: GenServer.call(pid, :status)

    @impl true
    def init(init), do: {:ok, init}

    @impl true
    def handle_call(:status, _from, init) do
      {:reply, Jido.AgentServer.status(init.agent_server), init}
    end
  end

  defmodule StablePlugin do
    use Jido.Plugin

    @impl true
    def child_spec(init),
      do: Supervisor.child_spec({StablePluginRuntime, init}, id: __MODULE__)

    @impl true
    def await_ready(runtime, _opts) do
      if Process.alive?(runtime), do: :ok, else: {:error, :not_ready}
    end
  end

  defmodule PluginCounter do
    use Jido.Agent,
      name: "durable_activation_plugin_counter",
      plugins: [StablePlugin]

    state do
      schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
    end

    routes do
      route "counter.add", Add
    end
  end

  defmodule Counter do
    use Jido.Agent, name: "durable_activation_counter"

    state do
      schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
    end

    routes do
      route "counter.add", Add
      route "counter.fail", Fail
      route "counter.large_step", LargeStep
      route "counter.large_join", LargeJoin
      route "counter.approval", Approval
      route "counter.delayed_increment", DelayedIncrement
    end
  end

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "jido_durable_activation_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)

    instance = unique_atom("instance")
    namespace = "jido/test/durable-activation/#{System.unique_integer([:positive])}"

    start_supervised!(
      {Jido,
       name: instance,
       namespace: namespace,
       persistence: {Jido.Persistence.File, path: path},
       activation: [idle_residency_timeout: 50]},
      id: instance
    )

    address = Address.new!(namespace: namespace, id: "counter")
    %{instance: instance, namespace: namespace, path: path, address: address}
  end

  @tag obligation: [
         "jido.agent_server.I95",
         "jido.agent_server.I103",
         "jido.agent_server.I104"
       ]
  test "Address delivery activates, stays warm, passivates, and restores", %{instance: instance, address: address} do
    assert {:ok, ^address} = Jido.create_agent(instance, address, Counter)
    assert {:error, :not_found} = Jido.resolve_agent(instance, address)

    assert %Status{
             residency: :passivated,
             work_state: :idle,
             agent_revision: 0,
             persistence_revision: 0
           } = Jido.status(instance, address)

    assert {:ok,
            %TurnResult{
              status: :committed,
              durability: :durable,
              agent_revision: 1,
              persistence_revision: 2,
              agent_activation_id: first_activation
            }} = Jido.call(instance, address, add(2))

    assert {:ok, first_server} = Jido.resolve_agent(instance, address)

    assert %Snapshot{agent: %{state: %{count: 2}}, agent_activation_id: ^first_activation} =
             Jido.AgentServer.snapshot(first_server)

    assert {:ok, %TurnResult{agent_activation_id: ^first_activation, agent_revision: 2}} =
             Jido.call(instance, address, add(3))

    first_root = activation_root(instance, address)
    monitor = Process.monitor(first_root)
    assert_receive {:DOWN, ^monitor, :process, ^first_root, _reason}, 2_000

    assert %Status{
             residency: :passivated,
             agent_revision: 2,
             persistence_revision: 4
           } = Jido.status(instance, address)

    assert {:ok,
            %TurnResult{
              agent_activation_id: second_activation,
              agent_revision: 3,
              persistence_revision: 6
            }} = Jido.call(instance, address, add(4))

    refute second_activation == first_activation
    assert {:ok, second_server} = Jido.resolve_agent(instance, address)
    assert %Snapshot{agent: %{state: %{count: 9}}} = Jido.AgentServer.snapshot(second_server)
  end

  @tag obligation: "jido.agent_server.I97"
  test "worker recovery keeps the activation identity", %{instance: instance, address: address} do
    assert {:ok, ^address} = Jido.create_agent(instance, address, Counter)

    assert {:ok, %TurnResult{agent_activation_id: activation_id}} =
             Jido.call(instance, address, add(1))

    assert {:ok, worker} = Jido.resolve_agent(instance, address)
    Process.exit(worker, :kill)

    replacement =
      eventually(fn ->
        case Jido.resolve_agent(instance, address) do
          {:ok, pid} when pid != worker -> pid
          _ -> nil
        end
      end)

    assert %Status{agent_activation_id: ^activation_id} = Jido.AgentServer.status(replacement)
    assert %Snapshot{agent: %{state: %{count: 1}}} = Jido.AgentServer.snapshot(replacement)
  end

  @tag obligation: "jido.agent_server.I96"
  test "an accepted failure is a TurnResult and does not change Agent state", %{instance: instance, address: address} do
    assert {:ok, ^address} = Jido.create_agent(instance, address, Counter)

    assert {:ok,
            %TurnResult{
              status: :failed,
              agent_revision: 0,
              persistence_revision: 2
            }} = Jido.call(instance, address, fail_signal())

    assert {:ok, server} = Jido.resolve_agent(instance, address)
    assert %Snapshot{agent: %{state: %{count: 0}}} = Jido.AgentServer.snapshot(server)
  end

  for {name, type} <- [step: "counter.large_step", join: "counter.large_join"] do
    @tag obligation: "jido.agent_server.I96"
    test "an oversized #{name} fact fails a durable Turn with its original cause", %{
      instance: instance,
      address: address
    } do
      assert {:ok, ^address} = Jido.create_agent(instance, address, Counter)
      assert {:ok, server} = Jido.activate_agent(instance, address)
      assert :ok = Server.await_ready(server)

      signal = Jido.Signal.new!(unquote(type), %{}, source: "/test")
      pending = Server.submit(server, signal)

      assert {:ok, %TurnResult{status: :failed, error: %CanonicalError{reason: {:limit, :byte_size, size}}}} =
               Server.await(pending, 10_000)

      assert size > 16 * 1024 * 1024
      assert %Snapshot{agent: %{state: %{count: 0}}} = Server.snapshot(server)
      assert {:ok, %TurnResult{status: :committed}} = Server.call(server, add(1))
      assert %Snapshot{agent: %{state: %{count: 1}}} = Server.snapshot(server)
    end
  end

  @tag obligation: "jido.agent_server.I105"
  test "an exact terminal result survives restart until acknowledgement", %{
    instance: instance,
    namespace: namespace,
    path: path,
    address: address
  } do
    assert {:ok, ^address} = Jido.create_agent(instance, address, Counter)

    turn_id = "product-operation-turn"

    pending =
      Jido.submit(instance, address, add(2),
        result_handoff: true,
        turn_id: turn_id
      )

    assert pending.turn_id == turn_id
    assert :ok = Jido.AgentServer.abandon(pending)

    result =
      Jido.Test.Eventually.eventually(fn ->
        case Jido.turn_result(instance, address, turn_id) do
          {:ok, result} -> result
          {:error, :not_found} -> false
        end
      end)

    assert %TurnResult{
             turn_id: ^turn_id,
             status: :committed,
             durability: :durable,
             completed_at: completed_at
           } = result

    assert is_integer(completed_at)
    assert %Status{admission: :blocked} = Jido.status(instance, address)
    assert {:error, :result_acknowledgement_required} = Jido.call(instance, address, add(1))
    assert {:error, :not_found} = Jido.turn_result(instance, address, "different-turn")

    assert {:error, :turn_result_mismatch} =
             Jido.acknowledge_turn_result(instance, address, "different-turn")

    assert {:ok, ^result} = Jido.turn_result(instance, address, turn_id)

    assert :ok = stop_supervised(instance)

    start_supervised!(
      {Jido,
       name: instance,
       namespace: namespace,
       persistence: {Jido.Persistence.File, path: path},
       activation: [idle_residency_timeout: 50]},
      id: instance
    )

    assert {:ok, ^result} = Jido.turn_result(instance, address, turn_id)
    assert :ok = Jido.acknowledge_turn_result(instance, address, turn_id)
    assert :ok = Jido.acknowledge_turn_result(instance, address, turn_id)
    assert {:error, :not_found} = Jido.turn_result(instance, address, turn_id)

    assert {:ok, %TurnResult{status: :committed}} = Jido.call(instance, address, add(1))
    assert {:ok, server} = Jido.resolve_agent(instance, address)
    assert %Snapshot{agent: %{state: %{count: 3}}} = Jido.AgentServer.snapshot(server)
  end

  @tag obligation: "jido.agent_server.I105"
  test "failed and cancelled handoffs retain process-neutral results", %{
    instance: instance,
    address: address
  } do
    assert {:ok, ^address} = Jido.create_agent(instance, address, Counter)

    failed = Jido.submit(instance, address, fail_signal(), result_handoff: true)

    assert {:ok, %TurnResult{status: :failed} = failed_result} =
             Jido.AgentServer.await(failed)

    assert {:ok, ^failed_result} = Jido.turn_result(instance, address, failed.turn_id)
    assert :ok = Jido.acknowledge_turn_result(instance, address, failed.turn_id)

    waiting =
      Jido.submit(instance, address, approval_request("cancel-request"), result_handoff: true)

    assert {:ok, %TurnResult{status: :waiting, turn_id: turn_id}} =
             Jido.AgentServer.await(waiting)

    assert :ok = Jido.cancel_turn(instance, address, turn_id)

    assert {:ok,
            %TurnResult{
              status: :cancelled,
              turn_id: ^turn_id,
              durability: :durable,
              error: :cancelled
            }} = Jido.turn_result(instance, address, turn_id)

    assert :ok = Jido.acknowledge_turn_result(instance, address, turn_id)
  end

  @tag obligation: "jido.agent_server.I95"
  test "delete uses only the Address and a tombstone prevents reactivation", %{instance: instance, address: address} do
    assert {:ok, ^address} = Jido.create_agent(instance, address, Counter)
    assert :ok = Jido.delete_agent(instance, address)
    assert {:error, :deleted} = Jido.activate_agent(instance, address)
    assert {:error, :deleted} = Jido.call(instance, address, add(1))
  end

  @tag obligation: "jido.agent_server.I98"
  test "a Signal resumes one durable Turn and exact retries return its saved result", %{
    instance: instance,
    address: address
  } do
    assert {:ok, ^address} = Jido.create_agent(instance, address, Counter)

    assert {:ok, %TurnResult{status: :waiting, turn_id: turn_id, waits: [_wait]}} =
             Jido.call(instance, address, approval_request("request-1"))

    assert {:ok, _first_server} = Jido.resolve_agent(instance, address)
    first_root = activation_root(instance, address)
    monitor = Process.monitor(first_root)
    assert_receive {:DOWN, ^monitor, :process, ^first_root, _reason}, 2_000

    approval = approval_signal("approval-1", "request-1")

    assert {:ok, %TurnResult{status: :committed, turn_id: ^turn_id} = completed} =
             Jido.call(instance, address, approval)

    assert {:ok, ^completed} = Jido.call(instance, address, approval)

    conflicting = approval_signal("approval-1", "other-request")
    assert {:error, :conflicting_input_id} = Jido.call(instance, address, conflicting)

    assert {:ok, server} = Jido.resolve_agent(instance, address)
    assert %Snapshot{agent: %{state: %{count: 1}}} = Jido.AgentServer.snapshot(server)
  end

  @tag obligation: "jido.agent_server.I99"
  test "the Instance restores a saved timer and wakes a passivated Agent after restart", %{
    instance: instance,
    namespace: namespace,
    path: path,
    address: address
  } do
    assert {:ok, ^address} = Jido.create_agent(instance, address, Counter)

    assert {:ok, %TurnResult{status: :waiting, turn_id: turn_id}} =
             Jido.call(instance, address, delayed_increment())

    assert :ok = stop_supervised(instance)

    start_supervised!(
      {Jido,
       name: instance,
       namespace: namespace,
       persistence: {Jido.Persistence.File, path: path},
       activation: [idle_residency_timeout: 50]},
      id: instance
    )

    server =
      eventually(fn ->
        case Jido.resolve_agent(instance, address) do
          {:ok, pid} ->
            case Jido.AgentServer.snapshot(pid) do
              %Snapshot{agent: %{state: %{count: 10}}} -> pid
              _other -> nil
            end

          _other ->
            nil
        end
      end)

    assert %Status{last_outcome: %{turn_id: ^turn_id}} = Jido.AgentServer.status(server)
  end

  @tag obligation: "jido.agent_server.I100"
  test "concurrent Address delivery joins one activation and serializes every Turn", %{
    instance: instance,
    address: address
  } do
    assert {:ok, ^address} = Jido.create_agent(instance, address, Counter)

    results =
      1..12
      |> Task.async_stream(fn _index -> Jido.call(instance, address, add(1)) end,
        ordered: true,
        max_concurrency: 12,
        timeout: 5_000
      )
      |> Enum.map(fn {:ok, {:ok, %TurnResult{} = result}} -> result end)

    assert 1 == results |> Enum.map(& &1.agent_activation_id) |> Enum.uniq() |> length()
    assert Enum.all?(results, &(&1.status == :committed))

    assert {:ok, server} = Jido.resolve_agent(instance, address)
    assert %Snapshot{agent: %{state: %{count: 12}}} = Jido.AgentServer.snapshot(server)
  end

  @tag obligation: "jido.agent_server.I101"
  test "an uncertain write faults the activation until the Instance reconciles it", %{
    namespace: file_namespace
  } do
    store = start_supervised!(Jido.Test.Persistence.ProbeStore)
    instance = unique_atom("uncertain")
    namespace = file_namespace <> "/uncertain"

    start_supervised!(
      {Jido,
       name: instance,
       namespace: namespace,
       persistence: {Jido.Test.Persistence.ProbeStore, store: store, write_result: :indeterminate, fault_revision: 2},
       activation: [idle_residency_timeout: 5_000]},
      id: instance
    )

    address = Address.new!(namespace: namespace, id: "counter")
    assert {:ok, ^address} = Jido.create_agent(instance, address, Counter)

    assert {:ok,
            %TurnResult{
              status: :uncertain,
              durability: :unknown,
              agent_revision: 0,
              persistence_revision: 1
            }} = Jido.call(instance, address, add(1))

    assert %Status{work_state: :faulted, admission: :blocked} = Jido.status(instance, address)
    assert {:error, :reconciliation_required} = Jido.call(instance, address, add(1))
    assert {:error, :reconciliation_required} = Jido.resolve_agent(instance, address)

    assert {:ok, reconciled} = Jido.reconcile_agent(instance, address)

    assert %Snapshot{agent: %{state: %{count: 1}}, agent_revision: 1} =
             Jido.AgentServer.snapshot(reconciled)

    assert {:ok, %TurnResult{status: :committed, agent_revision: 2}} =
             Jido.call(instance, address, add(1))
  end

  @tag obligation: "jido.agent_server.I102"
  test "an Instance definition upgrade replaces an idle activation", %{
    instance: instance,
    address: address
  } do
    assert {:ok, ^address} = Jido.create_agent(instance, address, Counter)
    assert {:ok, %TurnResult{agent_activation_id: first_id}} = Jido.call(instance, address, add(1))

    assert {:ok, ^address} = Jido.upgrade_agent(instance, address, Upgrade)
    assert {:ok, replacement} = Jido.resolve_agent(instance, address)

    assert %Snapshot{
             agent: %{vsn: 2, state: %{count: 101}},
             agent_activation_id: replacement_id,
             agent_revision: 2,
             persistence_revision: 3
           } = Jido.AgentServer.snapshot(replacement)

    refute replacement_id == first_id
  end

  @tag obligation: "jido.agent_server.I97"
  test "a worker restart keeps healthy Plugin runtime and its stable activation handle", %{
    instance: instance,
    namespace: namespace
  } do
    address = Address.new!(namespace: namespace, id: "plugin-counter")
    assert {:ok, ^address} = Jido.create_agent(instance, address, PluginCounter)
    assert {:ok, %TurnResult{agent_activation_id: activation_id}} = Jido.call(instance, address, add(1))
    assert {:ok, worker} = Jido.resolve_agent(instance, address)

    root = activation_root(instance, address)
    plugin_supervisor = Jido.AgentServer.Supervisor.plugin_supervisor(root)

    plugin = plugin_runtime(plugin_supervisor)

    assert is_pid(plugin)
    assert %Status{agent_activation_id: ^activation_id} = StablePluginRuntime.status(plugin)

    Process.exit(worker, :kill)

    replacement =
      eventually(fn ->
        case Jido.resolve_agent(instance, address) do
          {:ok, pid} when pid != worker -> pid
          _other -> nil
        end
      end)

    assert Process.alive?(plugin)
    assert %Status{agent_activation_id: ^activation_id} = StablePluginRuntime.status(plugin)
    assert replacement == Jido.AgentServer.ActivationHandle.whereis_name(root)

    Process.exit(plugin, :kill)

    {restarted_plugin, restarted_worker} =
      eventually(fn ->
        supervisor = Jido.AgentServer.Supervisor.plugin_supervisor(root)
        worker = Jido.AgentServer.Supervisor.live_worker(root)

        plugin = if is_pid(supervisor), do: plugin_runtime(supervisor)

        if is_pid(plugin) and is_pid(worker) and worker != replacement,
          do: {plugin, worker}
      end)

    refute restarted_plugin == plugin
    refute restarted_worker == replacement
    assert %Status{agent_activation_id: ^activation_id} = StablePluginRuntime.status(restarted_plugin)
  end

  defp add(by), do: Jido.Signal.new!("counter.add", %{by: by}, source: "/test")
  defp fail_signal, do: Jido.Signal.new!("counter.fail", %{}, source: "/test")

  defp approval_request(request_id),
    do: Jido.Signal.new!("counter.approval", %{request_id: request_id}, source: "/test")

  defp approval_signal(id, request_id),
    do:
      Jido.Signal.new!("counter.approved", %{request_id: request_id},
        id: id,
        source: "/test"
      )

  defp delayed_increment,
    do: Jido.Signal.new!("counter.delayed_increment", %{}, source: "/test")

  defp unique_atom(label),
    do: String.to_atom("jido_durable_activation_#{label}_#{System.unique_integer([:positive])}")

  defp activation_root(instance, address) do
    key = Jido.AgentServer.RegistrationGuard.registry_key(address.id, address.partition)
    [{root, {:activation, _activation_id}}] = Registry.lookup(Jido.Instance.Names.registry(instance), key)
    root
  end

  defp plugin_runtime(supervisor) do
    supervisor
    |> Supervisor.which_children()
    |> Enum.find_value(fn
      {{:plugin, StablePlugin}, pid, :worker, _modules} -> pid
      _child -> nil
    end)
  catch
    :exit, _reason -> nil
  end

  defp eventually(fun, attempts \\ 100)
  defp eventually(fun, 0), do: flunk("condition did not become true: #{inspect(fun.())}")

  defp eventually(fun, attempts) do
    case fun.() do
      nil ->
        Process.sleep(10)
        eventually(fun, attempts - 1)

      false ->
        Process.sleep(10)
        eventually(fun, attempts - 1)

      value ->
        value
    end
  end
end
