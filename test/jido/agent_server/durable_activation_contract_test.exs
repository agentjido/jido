defmodule Jido.AgentServer.DurableActivationContractTest do
  use Covenant.Case, component: "jido.agent_server", async: false

  alias Jido.Agent.Ref
  alias Jido.AgentServer.{Snapshot, Status, TurnResult}

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

  defmodule Approval do
    use Jido.Flow,
      name: "durable_activation_approval",
      schema: Jido.Joi.object(%{request_id: Jido.Joi.string()})

    flow do
      selection "decision" do
        await("approved",
          event: "counter.approved",
          match: %{request_id: input(:request_id)}
        )

        timer("expired", after_ms: 3_600_000)
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
      timer("delay", after_ms: 300)

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

    ref = Ref.new!(namespace: namespace, id: "counter")
    %{instance: instance, namespace: namespace, path: path, ref: ref}
  end

  @tag obligation: [
         "jido.agent_server.I95",
         "jido.agent_server.I103",
         "jido.agent_server.I104"
       ]
  test "Ref delivery activates, stays warm, passivates, and restores", %{instance: instance, ref: ref} do
    assert {:ok, ^ref} = Jido.create_agent(instance, ref, Counter)
    assert {:error, :not_found} = Jido.resolve_agent(instance, ref)

    assert %Status{
             residency: :passivated,
             work_state: :idle,
             agent_revision: 0,
             persistence_revision: 0
           } = Jido.status(instance, ref)

    assert {:ok,
            %TurnResult{
              status: :committed,
              durability: :durable,
              agent_revision: 1,
              persistence_revision: 2,
              agent_activation_id: first_activation
            }} = Jido.call(instance, ref, add(2))

    assert {:ok, first_server} = Jido.resolve_agent(instance, ref)

    assert %Snapshot{agent: %{state: %{count: 2}}, agent_activation_id: ^first_activation} =
             Jido.AgentServer.snapshot(first_server)

    assert {:ok, %TurnResult{agent_activation_id: ^first_activation, agent_revision: 2}} =
             Jido.call(instance, ref, add(3))

    first_root = activation_root(instance, ref)
    monitor = Process.monitor(first_root)
    assert_receive {:DOWN, ^monitor, :process, ^first_root, _reason}, 2_000

    assert %Status{
             residency: :passivated,
             agent_revision: 2,
             persistence_revision: 4
           } = Jido.status(instance, ref)

    assert {:ok,
            %TurnResult{
              agent_activation_id: second_activation,
              agent_revision: 3,
              persistence_revision: 6
            }} = Jido.call(instance, ref, add(4))

    refute second_activation == first_activation
    assert {:ok, second_server} = Jido.resolve_agent(instance, ref)
    assert %Snapshot{agent: %{state: %{count: 9}}} = Jido.AgentServer.snapshot(second_server)
  end

  @tag obligation: "jido.agent_server.I97"
  test "worker recovery keeps the activation identity", %{instance: instance, ref: ref} do
    assert {:ok, ^ref} = Jido.create_agent(instance, ref, Counter)

    assert {:ok, %TurnResult{agent_activation_id: activation_id}} =
             Jido.call(instance, ref, add(1))

    assert {:ok, worker} = Jido.resolve_agent(instance, ref)
    Process.exit(worker, :kill)

    replacement =
      eventually(fn ->
        case Jido.resolve_agent(instance, ref) do
          {:ok, pid} when pid != worker -> pid
          _ -> nil
        end
      end)

    assert %Status{agent_activation_id: ^activation_id} = Jido.AgentServer.status(replacement)
    assert %Snapshot{agent: %{state: %{count: 1}}} = Jido.AgentServer.snapshot(replacement)
  end

  @tag obligation: "jido.agent_server.I96"
  test "an accepted failure is a TurnResult and does not change Agent state", %{instance: instance, ref: ref} do
    assert {:ok, ^ref} = Jido.create_agent(instance, ref, Counter)

    assert {:ok,
            %TurnResult{
              status: :failed,
              agent_revision: 0,
              persistence_revision: 2
            }} = Jido.call(instance, ref, fail_signal())

    assert {:ok, server} = Jido.resolve_agent(instance, ref)
    assert %Snapshot{agent: %{state: %{count: 0}}} = Jido.AgentServer.snapshot(server)
  end

  @tag obligation: "jido.agent_server.I95"
  test "delete uses only the Ref and a tombstone prevents reactivation", %{instance: instance, ref: ref} do
    assert {:ok, ^ref} = Jido.create_agent(instance, ref, Counter)
    assert :ok = Jido.delete_agent(instance, ref)
    assert {:error, :deleted} = Jido.activate_agent(instance, ref)
    assert {:error, :deleted} = Jido.call(instance, ref, add(1))
  end

  @tag obligation: "jido.agent_server.I98"
  test "a Signal resumes one durable Turn and exact retries return its saved result", %{
    instance: instance,
    ref: ref
  } do
    assert {:ok, ^ref} = Jido.create_agent(instance, ref, Counter)

    assert {:ok, %TurnResult{status: :waiting, turn_id: turn_id, waits: [_wait]}} =
             Jido.call(instance, ref, approval_request("request-1"))

    assert {:ok, _first_server} = Jido.resolve_agent(instance, ref)
    first_root = activation_root(instance, ref)
    monitor = Process.monitor(first_root)
    assert_receive {:DOWN, ^monitor, :process, ^first_root, _reason}, 2_000

    approval = approval_signal("approval-1", "request-1")

    assert {:ok, %TurnResult{status: :committed, turn_id: ^turn_id} = completed} =
             Jido.call(instance, ref, approval)

    assert {:ok, ^completed} = Jido.call(instance, ref, approval)

    conflicting = approval_signal("approval-1", "other-request")
    assert {:error, :conflicting_input_id} = Jido.call(instance, ref, conflicting)

    assert {:ok, server} = Jido.resolve_agent(instance, ref)
    assert %Snapshot{agent: %{state: %{count: 1}}} = Jido.AgentServer.snapshot(server)
  end

  @tag obligation: "jido.agent_server.I99"
  test "the Instance restores a saved timer and wakes a passivated Agent after restart", %{
    instance: instance,
    namespace: namespace,
    path: path,
    ref: ref
  } do
    assert {:ok, ^ref} = Jido.create_agent(instance, ref, Counter)

    assert {:ok, %TurnResult{status: :waiting, turn_id: turn_id}} =
             Jido.call(instance, ref, delayed_increment())

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
        case Jido.resolve_agent(instance, ref) do
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
  test "concurrent Ref delivery joins one activation and serializes every Turn", %{
    instance: instance,
    ref: ref
  } do
    assert {:ok, ^ref} = Jido.create_agent(instance, ref, Counter)

    results =
      1..12
      |> Task.async_stream(fn _index -> Jido.call(instance, ref, add(1)) end,
        ordered: true,
        max_concurrency: 12,
        timeout: 5_000
      )
      |> Enum.map(fn {:ok, {:ok, %TurnResult{} = result}} -> result end)

    assert 1 == results |> Enum.map(& &1.agent_activation_id) |> Enum.uniq() |> length()
    assert Enum.all?(results, &(&1.status == :committed))

    assert {:ok, server} = Jido.resolve_agent(instance, ref)
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

    ref = Ref.new!(namespace: namespace, id: "counter")
    assert {:ok, ^ref} = Jido.create_agent(instance, ref, Counter)

    assert {:ok,
            %TurnResult{
              status: :uncertain,
              durability: :unknown,
              agent_revision: 0,
              persistence_revision: 1
            }} = Jido.call(instance, ref, add(1))

    assert %Status{work_state: :faulted, admission: :blocked} = Jido.status(instance, ref)
    assert {:error, :reconciliation_required} = Jido.call(instance, ref, add(1))
    assert {:error, :reconciliation_required} = Jido.resolve_agent(instance, ref)

    assert {:ok, reconciled} = Jido.reconcile_agent(instance, ref)

    assert %Snapshot{agent: %{state: %{count: 1}}, agent_revision: 1} =
             Jido.AgentServer.snapshot(reconciled)

    assert {:ok, %TurnResult{status: :committed, agent_revision: 2}} =
             Jido.call(instance, ref, add(1))
  end

  @tag obligation: "jido.agent_server.I102"
  test "an Instance definition upgrade replaces an idle activation", %{
    instance: instance,
    ref: ref
  } do
    assert {:ok, ^ref} = Jido.create_agent(instance, ref, Counter)
    assert {:ok, %TurnResult{agent_activation_id: first_id}} = Jido.call(instance, ref, add(1))

    assert {:ok, ^ref} = Jido.upgrade_agent(instance, ref, Upgrade)
    assert {:ok, replacement} = Jido.resolve_agent(instance, ref)

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
    ref = Ref.new!(namespace: namespace, id: "plugin-counter")
    assert {:ok, ^ref} = Jido.create_agent(instance, ref, PluginCounter)
    assert {:ok, %TurnResult{agent_activation_id: activation_id}} = Jido.call(instance, ref, add(1))
    assert {:ok, worker} = Jido.resolve_agent(instance, ref)

    root = activation_root(instance, ref)
    plugin_supervisor = Jido.AgentServer.Supervisor.plugin_supervisor(root)

    plugin = plugin_runtime(plugin_supervisor)

    assert is_pid(plugin)
    assert %Status{agent_activation_id: ^activation_id} = StablePluginRuntime.status(plugin)

    Process.exit(worker, :kill)

    replacement =
      eventually(fn ->
        case Jido.resolve_agent(instance, ref) do
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

  defp activation_root(instance, ref) do
    key = Jido.AgentServer.RegistrationGuard.registry_key(ref.id, ref.partition)
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
