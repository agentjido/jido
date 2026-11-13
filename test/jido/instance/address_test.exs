defmodule Jido.Instance.AddressTest do
  use ExUnit.Case, async: false
  use Covenant.Case, component: "jido.instance", async: false

  setup :ensure_namespace_registry

  import Jido.Test.Eventually

  alias Jido.Agent.Address
  alias Jido.Error
  alias Jido.Signal

  defp ensure_namespace_registry(context),
    do: Jido.Test.Instance.ContractSupport.ensure_namespace_registry(context)

  defmodule Add do
    use Jido.Action,
      name: "instance_ref_add",
      schema: Jido.Joi.object(%{by: Jido.Joi.integer()})

    @impl true
    def run(%{by: by}, context) do
      if observer = context[:observer], do: send(observer, {:add_started, self(), context})

      if context[:gate] do
        receive do
          :release -> :ok
        end
      end

      {:ok, %{context.agent_state | count: context.agent_state.count + by}}
    end
  end

  defmodule StatePlugin do
    use Jido.Plugin
    def state_spec(_opts), do: {:owned, Jido.Joi.integer() |> Jido.Joi.default(9)}
  end

  defmodule ReadyPlugin do
    use Jido.Plugin
    def child_spec(init), do: %{start: {Jido.Test.AgentServer.Resource, :start_link, [init]}}

    def await_ready(root, opts) do
      send(opts[:observer], {:ready_gate, self(), root})
      receive do: (:release -> :ok)
    end
  end

  defmodule Counter do
    use Jido.Agent, name: "instance_ref_counter"

    state do
      schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
    end

    routes do
      route "counter.add", Add
    end
  end

  defmodule ReadyAgent do
    use Jido.Agent,
      name: "instance_ref_ready",
      plugins: [{ReadyPlugin, %{observer: Jido.Instance.AddressTest.Observer}}]
  end

  defmodule StateAgent do
    use Jido.Agent, name: "instance_ref_state", plugins: [StatePlugin]
  end

  defmodule RenamedCounter do
    use Jido.Agent, name: "instance_ref_renamed_counter"

    state do
      schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
    end

    routes do
      route "counter.add", Add
    end
  end

  defmodule BadConfigInstance do
    use Jido, otp_app: :jido

    def config(_opts), do: :invalid
  end

  defmodule NamespacedInstance do
    use Jido, otp_app: :jido, namespace: "jido/test/generated-instance"
  end

  @removed_instance_facade [
    start_agent: [1, 2],
    stop_agent: [1, 2],
    whereis_agent: [1, 2],
    list_agents: [0, 1],
    agent_count: [0, 1],
    agent_address: [1, 2],
    resolve_agent: [1],
    create_agent: [2, 3],
    activate_agent: [2, 3],
    call: [2, 3],
    cast: [2],
    submit: [2, 3],
    await: [1, 2],
    abandon: [1],
    stop_agent_ref: [1, 2, 3],
    hibernate_ref: [1, 2],
    delete_agent: [2, 3],
    cancel: [1, 2],
    cancel_turn: [2, 3],
    attach_ref: [1, 2, 3],
    detach_ref: [1, 2, 3],
    touch_ref: [1],
    agent: [1, 2],
    plugin_state: [2, 3],
    status: [1, 2],
    children: [1, 2],
    await_ready: [1, 2],
    hibernate: [1, 2],
    thaw: [2, 3],
    debug: [0, 1],
    debug_status: [0]
  ]

  @tag obligation: "jido.instance.I1"
  test "a generated instance does not expose forwarding APIs" do
    Enum.each(@removed_instance_facade, fn {name, arities} ->
      Enum.each(arities, fn arity ->
        refute function_exported?(NamespacedInstance, name, arity)
      end)
    end)
  end

  @tag obligation: "jido.instance.I3"
  test "a namespace is exact, local, and unique while its instance is live" do
    namespace = unique_namespace("binding")
    first = unique_instance("first")
    second = unique_instance("second")

    first_pid = start_supervised!({Jido, name: first, namespace: namespace}, id: first)
    assert Jido.Instance.NamespaceRegistry.namespace(first) == namespace
    assert Jido.Instance.NamespaceRegistry.lookup(namespace) == {first, first_pid}

    assert {:error, %Error.ValidationError{} = error} =
             Jido.start_link(name: second, namespace: namespace)

    assert Error.code(error) == :jido_namespace_already_bound
    assert Process.whereis(second) == nil
  end

  @tag obligation: ["jido.instance.I2", "jido.instance.I3"]
  test "idempotent convenience startup keeps an existing namespace binding" do
    namespace = unique_namespace("idempotent")
    instance = unique_instance("idempotent")

    assert {:ok, pid} = Jido.start(name: instance, namespace: namespace)
    assert {:ok, ^pid} = Jido.start(name: instance, namespace: namespace)
    assert Jido.Instance.NamespaceRegistry.namespace(instance) == namespace
    assert :ok = Jido.stop(instance)
  end

  @tag obligation: "jido.instance.I6"
  test "a process label identifies each live server for one Agent Address" do
    namespace = unique_namespace("process-label")
    instance = unique_instance("process-label")
    start_durable_instance!(instance, namespace)

    address = Address.new!(namespace: namespace, partition: "west", id: "labelled-agent")
    first = create_and_activate(instance, address, Counter)
    label = {Jido.AgentServer, address.id}
    assert :proc_lib.get_label(first) == label

    monitor = Process.monitor(first)
    assert {:ok, %Jido.AgentServer.Snapshot{}} = Jido.AgentServer.stop(first)
    assert_receive {:DOWN, ^monitor, :process, ^first, _reason}

    assert {:ok, second} = Jido.activate_agent(instance, address)
    assert second != first
    assert :proc_lib.get_label(second) == label
  end

  @tag obligation: "jido.instance.I3"
  test "a failed instance start releases its namespace claim" do
    namespace = unique_namespace("released-claim")
    occupied = unique_instance("occupied")
    replacement = unique_instance("replacement")

    occupied_pid = start_supervised!({Jido, name: occupied}, id: occupied)

    assert {:error, {:already_started, ^occupied_pid}} =
             Jido.start_link(name: occupied, namespace: namespace)

    assert {:ok, replacement_pid} =
             start_supervised({Jido, name: replacement, namespace: namespace}, id: replacement)

    assert Jido.Instance.NamespaceRegistry.lookup(namespace) == {replacement, replacement_pid}
  end

  @tag obligation: "jido.instance.I1"
  test "instance options fail before a child starts" do
    name = unique_instance("invalid")

    assert {:error, %Error.ValidationError{} = start_error} = Jido.start(:invalid)
    assert Error.code(start_error) == :jido_instance_invalid_config

    for opts <- [
          [],
          [name: name, unknown: true],
          [name: name, namespace: ""],
          [name: name, max_tasks: -1],
          [name: name, debug: :invalid],
          [name: name, persistence: :not_an_adapter]
        ] do
      assert {:error, %Error.ValidationError{} = error} = Jido.start_link(opts)
      assert Error.code(error) == :jido_instance_invalid_config
      assert Process.whereis(name) == nil
    end

    assert {:error, %Error.ValidationError{}} = BadConfigInstance.start_link()
    assert {:error, %Error.ValidationError{}} = NamespacedInstance.start_link(:invalid)

    assert_raise Error.ValidationError, fn ->
      BadConfigInstance.child_spec()
    end

    assert_raise Error.ValidationError, fn ->
      NamespacedInstance.child_spec(:invalid)
    end
  end

  @tag obligation: "jido.instance.I6"
  test "an Address-first operation requires a stable instance namespace" do
    instance = unique_instance("namespace-required")
    start_supervised!({Jido, name: instance}, id: instance)

    assert {:error, %Error.ValidationError{} = error} = Jido.agent_address(instance, "counter")
    assert Error.code(error) == :jido_namespace_required
    assert error.details.instance == instance
  end

  @tag obligation: "jido.instance.I6"
  test "Address construction rejects invalid IDs and unknown options" do
    instance = unique_instance("address-validation")
    start_supervised!({Jido, name: instance, namespace: unique_namespace("address-validation")})

    assert {:error, id_error} = Jido.agent_address(instance, 12)
    assert Jido.Error.code(id_error) == :jido_instance_invalid_config
    assert id_error.details.id == 12

    assert {:error, option_error} = Jido.agent_address(instance, "counter", unknown: true)
    assert Jido.Error.code(option_error) == :jido_instance_invalid_config
    assert option_error.details.keys == [:unknown]

    assert {:error, value_error} = Jido.agent_address(instance, "counter", :invalid)
    assert value_error.details.value == :invalid
  end

  @tag obligation: "jido.instance.I1"
  test "instance options reject removed observation groups" do
    name = unique_instance("observation-config")

    for option <- [telemetry: [], observability: []] do
      assert {:error, %Error.ValidationError{} = error} =
               Jido.Instance.Options.validate([name: name] ++ option)

      assert Error.code(error) == :jido_instance_invalid_config
    end
  end

  @tag obligation: "jido.instance.I8"
  test "the Address API accepts a generated instance identity" do
    start_supervised!({NamespacedInstance, persistence: persistence("generated")})

    assert Jido.Instance.NamespaceRegistry.namespace(NamespacedInstance) ==
             "jido/test/generated-instance"

    assert {:ok, address} = Jido.agent_address(NamespacedInstance, "counter")
    server = create_and_activate(NamespacedInstance, address, Counter)
    assert Jido.resolve_agent(NamespacedInstance, address) == {:ok, server}

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(NamespacedInstance, address, signal(2))

    assert Jido.AgentServer.snapshot(server).agent.state.count == 2
  end

  @tag obligation: ["jido.instance.I6", "jido.instance.I7", "jido.instance.I8"]
  test "the Address API resolves each operation and preserves direct Server results" do
    namespace = unique_namespace("routing")
    instance = unique_instance("routing")
    start_durable_instance!(instance, namespace)

    assert {:ok, %Address{} = address} = Jido.agent_address(instance, "counter", partition: "west")
    assert address == Address.new!(namespace: namespace, partition: "west", id: "counter")
    server = create_and_activate(instance, address, Counter)
    assert Jido.resolve_agent(instance, address) == {:ok, server}
    assert Jido.AgentServer.await_ready(server) == :ok

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(instance, address, signal(2))

    assert Jido.AgentServer.snapshot(server).agent.state.count == 2
    assert %{work_state: :idle, residency: :active} = Jido.status(instance, address)

    assert :ok = Jido.cast(instance, address, signal(3))
    eventually(fn -> Jido.AgentServer.snapshot(server).agent.state.count == 5 end)

    pending = Jido.submit(instance, address, signal(4))

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.AgentServer.await(pending)

    assert Jido.AgentServer.snapshot(server).agent.state.count == 9

    missing = %{address | id: "missing"}
    assert {:error, :not_found} = Jido.resolve_agent(instance, missing)
    assert {:error, :not_found} = Jido.call(instance, missing, signal(1))

    wrong = %{address | namespace: namespace <> "/other"}
    assert {:error, %Error.ValidationError{} = error} = Jido.call(instance, wrong, signal(1))
    assert Error.code(error) == :jido_namespace_mismatch
    assert error.details.expected == namespace
    assert error.details.actual == wrong.namespace

    foreign = %{address | id: "foreign"}
    key = Jido.AgentServer.RegistrationGuard.registry_key(foreign.id, foreign.partition)
    assert {:ok, _} = Registry.register(Jido.Instance.Names.registry(instance), key, :ready)
    assert {:error, :not_found} = Jido.resolve_agent(instance, foreign)

    assert {:ok, %Jido.AgentServer.Snapshot{}} = Jido.AgentServer.stop(server)
    eventually(fn -> Jido.resolve_agent(instance, address) == {:error, :not_found} end)
  end

  @tag obligation: "jido.instance.I7"
  test "Address resolution distinguishes recovery and Registry loss" do
    namespace = unique_namespace("resolution")
    instance = unique_instance("resolution")
    instance_pid = start_durable_instance!(instance, namespace)
    address = Address.new!(namespace: namespace, id: "recovering")
    Process.register(self(), Jido.Instance.AddressTest.Observer)

    assert {:ok, ^address} = Jido.create_agent(instance, address, ReadyAgent)
    task = Task.async(fn -> Jido.activate_agent(instance, address) end)
    assert_receive {:ready_gate, gate, _root}, 1_000
    assert Jido.resolve_agent(instance, address) == {:error, :recovering}
    send(gate, :release)
    assert {:ok, server} = Task.await(task)
    assert Jido.AgentServer.await_ready(server) == :ok
    assert Jido.resolve_agent(instance, address) == {:ok, server}

    :sys.suspend(instance_pid)
    registry = Process.whereis(Jido.Instance.Names.registry(instance))
    monitor = Process.monitor(registry)

    try do
      Process.exit(registry, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^registry, _reason}, 1_000
      assert Jido.resolve_agent(instance, address) == {:error, :unavailable}
    after
      :sys.resume(instance_pid)
    end
  end

  @tag obligation: "jido.instance.I8"
  test "Address routing forwards context and explicit caller waits" do
    namespace = unique_namespace("routing")
    instance = unique_instance("routing")
    start_durable_instance!(instance, namespace)
    {:ok, address} = Jido.agent_address(instance, "counter")
    server = create_and_activate(instance, address, Counter)
    observer = unique_instance("routing-observer")
    Process.register(self(), observer)

    assert {:error, %Error.ValidationError{}} =
             Jido.call(instance, address, signal(1), timeout: -1)

    assert {:error, %Error.ValidationError{}} =
             Jido.submit(instance, address, signal(1), unknown: true)

    pending =
      Jido.submit(instance, address, signal(1), context: %{observer: observer, gate: true})

    assert_receive {:add_started, action, context}, 1_000
    assert context.observer == observer
    on_exit(fn -> if Process.alive?(action), do: send(action, :release) end)

    assert catch_exit(Jido.call(instance, address, signal(1), timeout: 0))

    assert {:error, %Error.ValidationError{}} = Jido.status(instance, address, -1)

    send(action, :release)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.AgentServer.await(pending)

    assert Jido.AgentServer.snapshot(server).agent.state.count == 1
  end

  @tag obligation: "jido.instance.I8"
  test "Address Plugin reads keep the selected Plugin" do
    namespace = unique_namespace("plugin-state")
    instance = unique_instance("plugin-state")
    start_durable_instance!(instance, namespace)
    address = Address.new!(namespace: namespace, id: "plugin-agent")

    server = create_and_activate(instance, address, StateAgent)
    assert Jido.AgentServer.snapshot(server).agent.state.owned == 9
  end

  @tag obligation: ["jido.instance.I3", "jido.instance.I6", "jido.instance.I8"]
  test "a durable Address survives rebinding its namespace to another local instance" do
    namespace = unique_namespace("durable")
    first = unique_instance("durable_first")
    second = unique_instance("durable_second")
    store = persistence("durable_address")
    address = Address.new!(namespace: namespace, partition: "team-a", id: "counter")

    start_supervised!(
      {Jido, name: first, namespace: namespace, persistence: store},
      id: first
    )

    assert {:ok, ^address} = Jido.create_agent(first, address, Counter)
    assert {:ok, server} = Jido.activate_agent(first, address)

    assert :ok = Jido.AgentServer.await_ready(server)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(first, address, signal(7))

    assert Jido.AgentServer.snapshot(server).agent.state.count == 7
    assert {:ok, %Jido.AgentServer.Snapshot{}} = Jido.AgentServer.stop(server)
    assert :ok = stop_supervised(first)

    start_supervised!(
      {Jido, name: second, namespace: namespace, persistence: store},
      id: second
    )

    assert {:ok, server} = Jido.activate_agent(second, address)
    assert :ok = Jido.AgentServer.await_ready(server)
    assert Jido.AgentServer.snapshot(server).agent.state.count == 7

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(second, address, signal(1))

    assert Jido.AgentServer.snapshot(server).agent.state.count == 8
    assert {:ok, %Jido.AgentServer.Snapshot{}} = Jido.AgentServer.stop(server)
    eventually(fn -> Jido.resolve_agent(second, address) == {:error, :not_found} end)
    assert :ok = Jido.delete_agent(second, address)

    assert {:error, :deleted} =
             Jido.Persistence.load_agent(store, Counter, address.id,
               namespace: namespace,
               partition: address.partition
             )

    case Jido.activate_agent(second, address) do
      {:ok, deleted} ->
        assert Jido.AgentServer.await_ready(deleted) == {:error, :deleted}

      {:error, :deleted} ->
        assert Jido.whereis_agent(second, address.id, partition: address.partition) == nil
    end
  end

  @tag obligation: ["jido.instance.I6", "jido.instance.I9"]
  test "durable Address creation is synchronous and activation is strict and single-flight" do
    namespace = unique_namespace("activation")
    instance = unique_instance("activation")
    store = persistence("activation")
    address = Address.new!(namespace: namespace, partition: "team-a", id: "counter")

    start_supervised!(
      {Jido, name: instance, namespace: namespace, persistence: store},
      id: instance
    )

    assert {:ok, ^address} = Jido.create_agent(instance, address, Counter)
    assert {:error, :not_found} = Jido.resolve_agent(instance, address)
    assert {:error, :conflict} = Jido.create_agent(instance, address, Counter)

    results =
      1..4
      |> Task.async_stream(
        fn _index -> Jido.activate_agent(instance, address) end,
        ordered: false,
        timeout: 5_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    servers = Enum.map(results, fn {:ok, server} -> server end)
    assert length(Enum.uniq(servers)) == 1
    server = hd(servers)
    assert :ok = Jido.AgentServer.await_ready(server)
    assert Jido.AgentServer.snapshot(server).agent.state.count == 0

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(instance, address, signal(7))

    assert Jido.AgentServer.snapshot(server).agent.state.count == 7
    assert {:ok, %Jido.AgentServer.Snapshot{}} = Jido.AgentServer.stop(server)

    assert {:ok, restored} = Jido.activate_agent(instance, address)
    assert :ok = Jido.AgentServer.await_ready(restored)
    assert Jido.AgentServer.snapshot(restored).agent.state.count == 7
  end

  @tag obligation: "jido.instance.I9"
  test "durable creation requires Instance persistence" do
    namespace = unique_namespace("create-persistence")
    instance = unique_instance("create-persistence")
    start_supervised!({Jido, name: instance, namespace: namespace}, id: instance)
    address = Address.new!(namespace: namespace, id: "counter")

    assert {:error, :persistence_not_configured} =
             Jido.create_agent(instance, address, Counter)

    assert {:error, :not_found} = Jido.resolve_agent(instance, address)
  end

  @tag obligation: "jido.instance.I9"
  test "strict activation does not create a missing durable Agent" do
    namespace = unique_namespace("strict-activation")
    instance = unique_instance("strict-activation")
    store = persistence("strict_activation")
    start_durable_instance!(instance, namespace, persistence: store)
    address = Address.new!(namespace: namespace, id: "missing")

    outcome =
      case Jido.activate_agent(instance, address) do
        {:ok, server} -> Jido.AgentServer.await_ready(server)
        {:error, reason} -> {:error, reason}
      end

    assert outcome == {:error, :not_found}

    assert {:error, :not_found} =
             Jido.Persistence.load_agent(store, Counter, address.id, namespace: namespace)
  end

  @tag obligation: "jido.instance.I6"
  test "Address creation rejects conflicting identity options before writing an Agent" do
    instance = unique_instance("address-options")
    start_durable_instance!(instance, unique_namespace("address-options"))
    {:ok, address} = Jido.agent_address(instance, "counter", partition: "west")

    for {key, value} <- [id: "other", partition: "east"] do
      assert {:error, %{details: %{key: ^key, value: ^value}}} =
               Jido.create_agent(instance, address, Counter, [{key, value}])
    end

    for {operation, opts, duplicate} <- [
          {:build, [partition: "west", partition: "east"], :partition},
          {:start, [id: address.id, id: "other"], :id}
        ] do
      result =
        case operation do
          :build -> Jido.agent_address(instance, "counter", opts)
          :start -> Jido.create_agent(instance, address, Counter, opts)
        end

      assert {:error, %Error.ValidationError{} = error} = result
      assert Error.code(error) == :jido_instance_invalid_config
      assert error.details.keys == [duplicate]
    end

    for opts <- [:invalid, [:invalid], %{id: "counter"}] do
      assert {:error, %{message: "Agent Address options must be a keyword list"}} =
               Jido.agent_address(instance, "counter", opts)

      assert {:error, %{message: "Agent Address create options must be a keyword list"}} =
               Jido.create_agent(instance, address, Counter, opts)

      assert {:error, %{message: "Agent Address delete options must be a unique keyword list"}} =
               Jido.delete_agent(instance, address, opts)
    end

    assert Jido.resident_agent_count(instance) == 0

    assert {:ok, ^address} =
             Jido.create_agent(instance, address, Counter, id: address.id, partition: address.partition)

    assert {:ok, server} = Jido.activate_agent(instance, address)
    assert :ok = Jido.AgentServer.await_ready(server)

    assert Jido.resolve_agent(instance, address) == {:ok, server}
    assert {:error, :agent_running} = Jido.delete_agent(instance, address)
    assert Jido.AgentServer.snapshot(server).agent.state == %{count: 0}
  end

  @tag obligation: "jido.instance.I8"
  test "Address controls preserve AgentServer results across passivation" do
    instance = unique_instance("address-controls")
    start_durable_instance!(instance, unique_namespace("address-controls"))
    {:ok, address} = Jido.agent_address(instance, "counter")
    server = create_and_activate(instance, address, Counter)

    assert Jido.cancel_turn(instance, address, "absent") ==
             Jido.AgentServer.cancel_turn(server, "absent")

    assert Jido.status(instance, address) == Jido.AgentServer.status(server)
    assert {:error, %Error.ValidationError{}} = Jido.cancel_turn(instance, address, "absent", -1)

    assert {:ok, %Jido.AgentServer.Snapshot{}} = Jido.AgentServer.stop(server)
    eventually(fn -> Jido.status(instance, address).residency == :passivated end)
    assert Jido.cancel_turn(instance, address, "absent") == {:error, :not_running}
  end

  @tag obligation: "jido.instance.I8"
  test "activation stop forwards the reason" do
    instance = unique_instance("address-stop")
    start_durable_instance!(instance, unique_namespace("address-stop"))

    {:ok, reason_address} = Jido.agent_address(instance, "reason")
    reason_server = create_and_activate(instance, reason_address, Counter)
    reason_monitor = Process.monitor(reason_server)

    assert {:ok, %Jido.AgentServer.Snapshot{}} =
             Jido.AgentServer.stop(reason_server, :contract_stop)

    assert_receive {:DOWN, ^reason_monitor, :process, ^reason_server, {:shutdown, :contract_stop}}
  end

  defp signal(by) do
    Signal.new!("counter.add", %{by: by}, source: "/instance-address-test")
  end

  defp start_durable_instance!(instance, namespace, opts \\ []) do
    config =
      Keyword.merge(
        [name: instance, namespace: namespace, persistence: persistence("instance")],
        opts
      )

    start_supervised!({Jido, config}, id: instance)
  end

  defp create_and_activate(instance, address, agent, opts \\ []) do
    assert {:ok, ^address} = Jido.create_agent(instance, address, agent, opts)
    assert {:ok, server} = Jido.activate_agent(instance, address)
    assert :ok = Jido.AgentServer.await_ready(server)
    server
  end

  defp persistence(label) do
    table = String.to_atom("instance_ref_#{label}_#{System.unique_integer([:positive])}")
    {Jido.Persistence.ETS, table: table}
  end

  defp unique_instance(label) do
    String.to_atom("jido_instance_ref_#{label}_#{System.unique_integer([:positive])}")
  end

  defp unique_namespace(label) do
    "jido/test/#{label}/#{System.unique_integer([:positive])}"
  end
end
