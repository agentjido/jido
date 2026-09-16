defmodule JidoTest.InstanceRefTest do
  use ExUnit.Case, async: true

  import JidoTest.Eventually

  alias Jido.Agent.Ref
  alias Jido.Error
  alias Jido.Persistence
  alias Jido.Signal

  defmodule Add do
    use Jido.Action,
      name: "instance_ref_add",
      schema: Zoi.object(%{by: Zoi.integer()})

    @impl true
    def run(%{by: by}, context) do
      {:ok, %{context.agent_state | count: context.agent_state.count + by}}
    end
  end

  defmodule Counter do
    use Jido.Agent,
      name: "instance_ref_counter",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
      routes: [{"counter.add", Add}]
  end

  defmodule RenamedCounter do
    use Jido.Agent,
      name: "instance_ref_renamed_counter",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
      routes: [{"counter.add", Add}]
  end

  defmodule BadConfigInstance do
    use Jido, otp_app: :jido

    def config(_opts), do: :invalid
  end

  defmodule NamespacedInstance do
    use Jido, otp_app: :jido, namespace: "jido/test/generated-instance"
  end

  @ref_api_contract [
    {:agent_ref, [1, 2], :agent_ref, [2, 3]},
    {:resolve_agent, [1], :resolve_agent, [2]},
    {:start_agent_ref, [2, 3], :start_agent_ref, [3, 4]},
    {:activate_agent, [2, 3], :activate_agent, [3, 4]},
    {:call, [2, 3], :call, [3, 4]},
    {:cast, [2], :cast, [3]},
    {:send_request, [2, 3], :send_request, [3, 4]},
    {:receive_response, [1, 2], :receive_response, [1, 2]},
    {:stop_agent_ref, [1, 2, 3], :stop_agent_ref, [2, 3, 4]},
    {:hibernate_ref, [1, 2], :hibernate_ref, [2, 3]},
    {:delete_agent, [2, 3], :delete_agent, [3, 4]},
    {:cancel, [1, 2], :cancel, [2, 3]},
    {:cancel_turn, [2, 3], :cancel_turn, [3, 4]},
    {:attach_ref, [1, 2, 3], :attach, [2, 3, 4]},
    {:detach_ref, [1, 2, 3], :detach, [2, 3, 4]},
    {:touch_ref, [1], :touch, [2]},
    {:agent, [1, 2], :agent, [2, 3]},
    {:plugin_state, [2, 3], :plugin_state, [3, 4]},
    {:status, [1, 2], :status, [2, 3]},
    {:snapshot, [1, 2], :snapshot, [2, 3]},
    {:children, [1, 2], :children, [2, 3]},
    {:await_ready, [1, 2], :await_ready, [2, 3]},
    {:set_agent_debug, [2, 3], :set_agent_debug, [3, 4]},
    {:recent_events, [1, 2, 3], :recent_events, [2, 3, 4]}
  ]

  test "a generated instance exposes the complete Ref-first API" do
    Enum.each(@ref_api_contract, fn {generated_name, generated_arities, root_name, root_arities} ->
      assert Enum.all?(
               generated_arities,
               &function_exported?(NamespacedInstance, generated_name, &1)
             )

      assert Enum.all?(root_arities, &function_exported?(Jido, root_name, &1))
    end)
  end

  test "a namespace is exact, local, and unique while its instance is live" do
    namespace = unique_namespace("binding")
    first = unique_instance("first")
    second = unique_instance("second")

    first_pid = start_supervised!({Jido, name: first, namespace: namespace}, id: first)
    assert Jido.namespace(first) == namespace
    assert Jido.Instance.NamespaceRegistry.lookup(namespace) == {first, first_pid}

    assert {:error, %Error.ValidationError{} = error} =
             Jido.start_link(name: second, namespace: namespace)

    assert Error.code(error) == :jido_namespace_already_bound
    assert Process.whereis(second) == nil
  end

  test "idempotent convenience startup keeps an existing namespace binding" do
    namespace = unique_namespace("idempotent")
    instance = unique_instance("idempotent")

    assert {:ok, pid} = Jido.start(name: instance, namespace: namespace)
    assert {:ok, ^pid} = Jido.start(name: instance, namespace: namespace)
    assert Jido.namespace(instance) == namespace
    assert :ok = Jido.stop(instance)
  end

  test "a Registry restart preserves one live Agent identity and Ref resolution" do
    instance = unique_instance("registry-recovery")
    namespace = unique_namespace("registry-recovery")
    instance_pid = start_supervised!({Jido, name: instance, namespace: namespace}, id: instance)
    ref = Ref.new!(namespace: namespace, id: "registry-agent")
    assert {:ok, server} = Jido.start_agent_ref(instance, ref, Counter)

    signal = Signal.new!("counter.add", %{by: 4}, source: "/test")
    assert {:ok, %{state: %{count: 4}}} = Jido.AgentServer.call(server, signal)

    registry = Jido.registry_name(instance)
    old_guard = Process.whereis(Jido.registration_guard_name(instance))
    old_registry = Process.whereis(registry)
    assert :ok = :sys.suspend(server)

    try do
      Process.exit(old_registry, :kill)

      eventually(fn ->
        current = Process.whereis(registry)
        is_pid(current) and current != old_registry
      end)

      assert Process.whereis(Jido.registration_guard_name(instance)) == old_guard
      assert Process.alive?(server)
      assert Jido.whereis_agent(instance, ref.id) == nil

      assert {:error, {:already_started, ^server}} =
               Jido.start_agent_ref(instance, ref, Counter)
    after
      assert :ok = :sys.resume(server)
    end

    eventually(fn -> Jido.resolve_agent(instance, ref) == {:ok, server} end)
    assert Jido.whereis_agent(instance, ref.id) == server
    assert Jido.AgentServer.snapshot(server).agent.state.count == 4

    assert {:error, {:already_started, ^server}} = Jido.start_agent_ref(instance, ref, Counter)

    monitor = Process.monitor(server)
    assert :ok = Jido.stop_agent_ref(instance, ref)
    assert_receive {:DOWN, ^monitor, :process, ^server, _reason}
    eventually(fn -> Jido.resolve_agent(instance, ref) == {:error, :not_found} end)

    assert {:ok, replacement} = Jido.start_agent_ref(instance, ref, Counter)
    assert replacement != server
    assert Process.alive?(instance_pid)
  end

  test "a process label identifies each live server for one Agent Ref" do
    namespace = unique_namespace("process-label")
    instance = unique_instance("process-label")
    start_supervised!({Jido, name: instance, namespace: namespace}, id: instance)

    ref = Ref.new!(namespace: namespace, partition: "west", id: "labelled-agent")
    assert {:ok, first} = Jido.start_agent_ref(instance, ref, Counter)
    label = {:jido_agent, ref.namespace, ref.partition, ref.id}
    assert :proc_lib.get_label(first) == label

    monitor = Process.monitor(first)
    assert :ok = Jido.stop_agent_ref(instance, ref)
    assert_receive {:DOWN, ^monitor, :process, ^first, _reason}

    assert {:ok, second} = Jido.start_agent_ref(instance, ref, Counter)
    assert second != first
    assert :proc_lib.get_label(second) == label
  end

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

  test "a Ref-first operation requires a stable instance namespace" do
    instance = unique_instance("namespace-required")
    start_supervised!({Jido, name: instance}, id: instance)

    assert {:error, %Error.ValidationError{} = error} = Jido.agent_ref(instance, "counter")
    assert Error.code(error) == :jido_namespace_required
  end

  test "instance options reject removed observation groups" do
    name = unique_instance("observation-config")

    for option <- [telemetry: [], observability: []] do
      assert {:error, %Error.ValidationError{} = error} =
               Jido.Instance.Options.validate([name: name] ++ option)

      assert Error.code(error) == :jido_instance_invalid_config
    end
  end

  test "a generated instance exposes the same Ref-first facade" do
    start_supervised!(NamespacedInstance)
    assert NamespacedInstance.namespace() == "jido/test/generated-instance"
    assert {:ok, ref} = NamespacedInstance.agent_ref("counter")
    assert {:ok, server} = NamespacedInstance.start_agent_ref(ref, Counter)
    assert NamespacedInstance.resolve_agent(ref) == {:ok, server}
    assert {:ok, agent} = NamespacedInstance.call(ref, signal(2))
    assert agent.state.count == 2
  end

  test "the Ref facade resolves each operation and preserves direct Server results" do
    namespace = unique_namespace("facade")
    instance = unique_instance("facade")
    start_supervised!({Jido, name: instance, namespace: namespace}, id: instance)

    assert {:ok, %Ref{} = ref} = Jido.agent_ref(instance, "counter", partition: "west")
    assert ref == Ref.new!(namespace: namespace, partition: "west", id: "counter")
    assert {:ok, server} = Jido.start_agent_ref(instance, ref, Counter)
    assert Jido.resolve_agent(instance, ref) == {:ok, server}
    assert Jido.await_ready(instance, ref) == :ok

    assert {:ok, committed} = Jido.call(instance, ref, signal(2))
    assert committed.state.count == 2
    assert Jido.agent(instance, ref) == committed
    assert Jido.snapshot(instance, ref) == %{agent: committed, state_version: 1}
    assert %{phase: :idle, state_version: 1} = Jido.status(instance, ref)
    assert is_map(Jido.children(instance, ref))

    assert :ok = Jido.cast(instance, ref, signal(3))
    eventually(fn -> Jido.agent(instance, ref).state.count == 5 end)

    request = Jido.send_request(instance, ref, signal(4))
    assert {:reply, {:ok, requested}} = Jido.receive_response(request)
    assert requested.state.count == 9

    assert :ok = Jido.set_agent_debug(instance, ref, true)
    assert {:ok, events} = Jido.recent_events(instance, ref)
    assert is_list(events)

    missing = %{ref | id: "missing"}
    assert {:error, :not_found} = Jido.resolve_agent(instance, missing)
    assert {:error, :not_found} = Jido.call(instance, missing, signal(1))

    wrong = %{ref | namespace: namespace <> "/other"}
    assert {:error, %Error.ValidationError{} = error} = Jido.call(instance, wrong, signal(1))
    assert Error.code(error) == :jido_namespace_mismatch

    assert :ok = Jido.stop_agent_ref(instance, ref)
    eventually(fn -> Jido.resolve_agent(instance, ref) == {:error, :not_found} end)
  end

  test "a durable Ref survives rebinding its namespace to another local instance" do
    namespace = unique_namespace("durable")
    first = unique_instance("durable_first")
    second = unique_instance("durable_second")
    store = persistence("durable_ref")
    ref = Ref.new!(namespace: namespace, partition: "team-a", id: "counter")

    start_supervised!(
      {Jido, name: first, namespace: namespace, persistence: store},
      id: first
    )

    assert {:ok, _server} =
             Jido.start_agent_ref(first, ref, Counter, restore: false)

    assert {:ok, agent} = Jido.call(first, ref, signal(7))
    assert agent.state.count == 7
    assert :ok = Jido.hibernate_ref(first, ref)
    assert :ok = stop_supervised(first)

    start_supervised!(
      {Jido, name: second, namespace: namespace, persistence: store},
      id: second
    )

    assert {:error, {:invalid_persistence_record, :agent_module}} =
             Jido.activate_agent(second, ref, RenamedCounter)

    assert {:ok, _server} = Jido.activate_agent(second, ref, Counter)
    assert Jido.agent(second, ref).state.count == 7
    assert {:ok, restored} = Jido.call(second, ref, signal(1))
    assert restored.state.count == 8
    assert :ok = Jido.hibernate_ref(second, ref)
    assert :ok = Jido.delete_agent(second, ref, Counter)
    assert {:error, :deleted} = Jido.activate_agent(second, ref, Counter)
  end

  test "Ref startup rejects conflicting identity options before starting an Agent" do
    instance = unique_instance("ref-options")
    start_supervised!({Jido, name: instance, namespace: unique_namespace("ref-options")})
    {:ok, ref} = Jido.agent_ref(instance, "counter", partition: "west")

    for {key, value} <- [id: "other", partition: "east"] do
      assert {:error, %{details: %{key: ^key, value: ^value}}} =
               Jido.start_agent_ref(instance, ref, Counter, [{key, value}])
    end

    for opts <- [:invalid, [:invalid], %{id: "counter"}] do
      assert {:error, %{message: "Ref facade options must be a keyword list"}} =
               Jido.agent_ref(instance, "counter", opts)

      assert {:error, %{message: "Ref facade options must be a keyword list"}} =
               Jido.start_agent_ref(instance, ref, Counter, opts)

      assert {:error, %{message: "Ref facade options must be a keyword list"}} =
               Jido.delete_agent(instance, ref, Counter, opts)
    end

    assert Jido.agent_count(instance) == 0

    assert {:ok, server} =
             Jido.start_agent_ref(instance, ref, Counter, id: ref.id, partition: ref.partition)

    assert Jido.resolve_agent(instance, ref) == {:ok, server}
    assert {:error, :agent_running} = Jido.delete_agent(instance, ref, Counter)
    assert Jido.agent(instance, ref).state == %{count: 0}
  end

  test "Ref runtime controls preserve their Server results and reject a missing activation" do
    instance = unique_instance("ref-controls")
    start_supervised!({Jido, name: instance, namespace: unique_namespace("ref-controls")})
    {:ok, ref} = Jido.agent_ref(instance, "counter")
    {:ok, server} = Jido.start_agent_ref(instance, ref, Counter)

    assert Jido.cancel(instance, ref) == Jido.AgentServer.cancel(server)

    assert Jido.cancel_turn(instance, ref, "absent") ==
             Jido.AgentServer.cancel_turn(server, "absent")

    assert :ok = Jido.attach(instance, ref)
    assert Jido.AgentServer.status(server).runtime.lifecycle.attached == 1
    assert :ok = Jido.touch(instance, ref)
    assert :ok = Jido.detach(instance, ref)
    assert Jido.AgentServer.status(server).runtime.lifecycle.attached == 0

    assert Jido.plugin_state(instance, ref, __MODULE__) ==
             Jido.AgentServer.plugin_state(server, __MODULE__)

    assert :ok = Jido.stop_agent_ref(instance, ref)

    for operation <- [
          &Jido.cancel(instance, &1),
          &Jido.cancel_turn(instance, &1, "absent"),
          &Jido.attach(instance, &1),
          &Jido.detach(instance, &1),
          &Jido.touch(instance, &1),
          &Jido.plugin_state(instance, &1, __MODULE__)
        ] do
      assert {:error, :not_found} = operation.(ref)
    end
  end

  test "namespaced storage detects dual-key collisions and still reads one legacy key" do
    namespace = unique_namespace("collision")
    legacy_instance = unique_instance("legacy")
    ref_instance = unique_instance("ref")
    store = persistence("collision")
    agent = Counter.new!(id: "counter")
    ref = Ref.new!(namespace: namespace, partition: nil, id: agent.id)

    assert :ok = Persistence.save_agent(store, agent, instance: legacy_instance)

    assert {:ok, ^agent} =
             Persistence.load_agent(store, Counter, agent.id,
               instance: legacy_instance,
               namespace: namespace
             )

    updated = %{agent | state: %{count: 1}}

    assert :ok =
             Persistence.save_agent(store, updated,
               instance: legacy_instance,
               namespace: namespace,
               revision: 1,
               expected_revision: 0
             )

    legacy_key = Persistence.agent_key(legacy_instance, Counter, agent.id)
    ref_key = Persistence.agent_key(ref)
    adapter_opts = elem(store, 1)

    assert {:error, :not_found} = Jido.Persistence.ETS.get(ref_key, adapter_opts)
    assert {:ok, legacy_bytes} = Jido.Persistence.ETS.get(legacy_key, adapter_opts)
    assert {:ok, %{format: 2, kind: :active}} = Jido.Persistence.Record.decode(legacy_bytes)

    assert :ok =
             Persistence.save_agent(store, agent,
               instance: ref_instance,
               namespace: namespace
             )

    assert {:ok, ref_bytes} = Jido.Persistence.ETS.get(ref_key, adapter_opts)

    assert {:ok,
            %{
              format: 3,
              kind: :active,
              namespace: ^namespace,
              agent_module: Counter
            }} = Jido.Persistence.Record.decode(ref_bytes)

    assert {:error, {:persistence_identity_collision, keys}} =
             Persistence.load_agent(store, Counter, agent.id,
               instance: legacy_instance,
               namespace: namespace
             )

    assert keys.legacy_key == legacy_key
    assert keys.ref_key == ref_key
  end

  defp signal(by) do
    Signal.new!("counter.add", %{by: by}, source: "/instance-ref-test")
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
