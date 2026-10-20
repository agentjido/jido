Code.require_file("support.ex", __DIR__)

defmodule JidoTest.InstanceRefTest do
  use ExUnit.Case, async: false
  use Covenant.Case, component: "jido.instance", async: false

  setup :ensure_namespace_registry

  import JidoTest.Eventually

  alias Jido.Agent.Ref
  alias Jido.Error
  alias Jido.Signal

  defp ensure_namespace_registry(context),
    do: JidoTest.InstanceContractSupport.ensure_namespace_registry(context)

  defmodule Add do
    use Jido.Action,
      name: "instance_ref_add",
      schema: Zoi.object(%{by: Zoi.integer()})

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
    def state_spec(_opts), do: {:owned, Zoi.integer() |> Zoi.default(9)}
  end

  defmodule ReadyResource do
    use GenServer
    def start_link(init), do: GenServer.start_link(__MODULE__, init)
    @impl true
    def init(init), do: {:ok, init}
  end

  defmodule ReadyPlugin do
    use Jido.Plugin
    def child_spec(init), do: %{start: {ReadyResource, :start_link, [init]}}

    def await_ready(root, opts) do
      send(opts[:observer], {:ready_gate, self(), root})
      receive do: (:release -> :ok)
    end
  end

  defmodule Counter do
    use Jido.Agent, name: "instance_ref_counter"

    agent do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      route "counter.add", Add
    end
  end

  defmodule RenamedCounter do
    use Jido.Agent, name: "instance_ref_renamed_counter"

    agent do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
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

  @ref_api_contract [
    {:agent_ref, [1, 2], :agent_ref, [2, 3]},
    {:resolve_agent, [1], :resolve_agent, [2]},
    {:start_agent_ref, [2, 3], :start_agent_ref, [3, 4]},
    {:activate_agent, [2, 3], :activate_agent, [3, 4]},
    {:call, [2, 3], :call, [3, 4]},
    {:cast, [2], :cast, [3]},
    {:submit, [2, 3], :submit, [3, 4]},
    {:await, [1, 2], :await, [1, 2]},
    {:abandon, [1], :abandon, [1]},
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
    {:children, [1, 2], :children, [2, 3]},
    {:await_ready, [1, 2], :await_ready, [2, 3]}
  ]

  @tag obligation: "jido.instance.I8"
  test "a generated instance exposes the complete Ref-first API" do
    Enum.each(@ref_api_contract, fn {generated_name, generated_arities, root_name, root_arities} ->
      assert Enum.all?(
               generated_arities,
               &function_exported?(NamespacedInstance, generated_name, &1)
             )

      assert Enum.all?(root_arities, &function_exported?(Jido, root_name, &1))
    end)
  end

  @tag obligation: "jido.instance.I3"
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

  @tag obligation: ["jido.instance.I2", "jido.instance.I3"]
  test "idempotent convenience startup keeps an existing namespace binding" do
    namespace = unique_namespace("idempotent")
    instance = unique_instance("idempotent")

    assert {:ok, pid} = Jido.start(name: instance, namespace: namespace)
    assert {:ok, ^pid} = Jido.start(name: instance, namespace: namespace)
    assert Jido.namespace(instance) == namespace
    assert :ok = Jido.stop(instance)
  end

  @tag obligation: "jido.instance.I6"
  test "a process label identifies each live server for one Agent Ref" do
    namespace = unique_namespace("process-label")
    instance = unique_instance("process-label")
    start_supervised!({Jido, name: instance, namespace: namespace}, id: instance)

    ref = Ref.new!(namespace: namespace, partition: "west", id: "labelled-agent")
    assert {:ok, first} = Jido.start_agent_ref(instance, ref, Counter)
    label = {Jido.AgentServer, ref.id}
    assert :proc_lib.get_label(first) == label

    monitor = Process.monitor(first)
    assert :ok = Jido.stop_agent_ref(instance, ref)
    assert_receive {:DOWN, ^monitor, :process, ^first, _reason}

    assert {:ok, second} = Jido.start_agent_ref(instance, ref, Counter)
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
  test "a Ref-first operation requires a stable instance namespace" do
    instance = unique_instance("namespace-required")
    start_supervised!({Jido, name: instance}, id: instance)

    assert {:error, %Error.ValidationError{} = error} = Jido.agent_ref(instance, "counter")
    assert Error.code(error) == :jido_namespace_required
    assert error.details.instance == instance
  end

  @tag obligation: "jido.instance.I6"
  test "Ref construction rejects invalid IDs and unknown options" do
    instance = unique_instance("ref-validation")
    start_supervised!({Jido, name: instance, namespace: unique_namespace("ref-validation")})

    assert {:error, id_error} = Jido.agent_ref(instance, 12)
    assert Jido.Error.code(id_error) == :jido_instance_invalid_config
    assert id_error.details.id == 12

    assert {:error, option_error} = Jido.agent_ref(instance, "counter", unknown: true)
    assert Jido.Error.code(option_error) == :jido_instance_invalid_config
    assert option_error.details.keys == [:unknown]

    assert {:error, value_error} = Jido.agent_ref(instance, "counter", :invalid)
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
  test "a generated instance exposes the same Ref-first facade" do
    start_supervised!(NamespacedInstance)
    assert NamespacedInstance.namespace() == "jido/test/generated-instance"
    assert {:ok, ref} = NamespacedInstance.agent_ref("counter")
    assert {:ok, server} = NamespacedInstance.start_agent_ref(ref, Counter)
    assert NamespacedInstance.resolve_agent(ref) == {:ok, server}
    assert {:ok, agent, _} = NamespacedInstance.call(ref, signal(2))
    assert agent.state.count == 2
  end

  @tag obligation: ["jido.instance.I6", "jido.instance.I7", "jido.instance.I8"]
  test "the Ref facade resolves each operation and preserves direct Server results" do
    namespace = unique_namespace("facade")
    instance = unique_instance("facade")
    start_supervised!({Jido, name: instance, namespace: namespace}, id: instance)

    assert {:ok, %Ref{} = ref} = Jido.agent_ref(instance, "counter", partition: "west")
    assert ref == Ref.new!(namespace: namespace, partition: "west", id: "counter")
    assert {:ok, server} = Jido.start_agent_ref(instance, ref, Counter)
    assert Jido.resolve_agent(instance, ref) == {:ok, server}
    assert Jido.await_ready(instance, ref) == :ok

    assert {:ok, committed, _} = Jido.call(instance, ref, signal(2))
    assert committed.state.count == 2
    assert Jido.agent(instance, ref) == committed
    assert %{phase: :idle, state_version: 1} = Jido.status(instance, ref)
    assert is_map(Jido.children(instance, ref))

    assert :ok = Jido.cast(instance, ref, signal(3))
    eventually(fn -> Jido.agent(instance, ref).state.count == 5 end)

    pending = Jido.submit(instance, ref, signal(4))
    assert {:ok, requested, _} = Jido.await(pending)
    assert requested.state.count == 9

    missing = %{ref | id: "missing"}
    assert {:error, :not_found} = Jido.resolve_agent(instance, missing)
    assert {:error, :not_found} = Jido.call(instance, missing, signal(1))

    wrong = %{ref | namespace: namespace <> "/other"}
    assert {:error, %Error.ValidationError{} = error} = Jido.call(instance, wrong, signal(1))
    assert Error.code(error) == :jido_namespace_mismatch
    assert error.details.expected == namespace
    assert error.details.actual == wrong.namespace

    foreign = %{ref | id: "foreign"}
    key = Jido.AgentServer.RegistrationGuard.registry_key(foreign.id, foreign.partition)
    assert {:ok, _} = Registry.register(Jido.registry_name(instance), key, :ready)
    assert {:error, :not_found} = Jido.resolve_agent(instance, foreign)

    assert :ok = Jido.stop_agent_ref(instance, ref)
    eventually(fn -> Jido.resolve_agent(instance, ref) == {:error, :not_found} end)
  end

  @tag obligation: "jido.instance.I7"
  test "Ref resolution distinguishes recovery and Registry loss" do
    namespace = unique_namespace("resolution")
    instance = unique_instance("resolution")
    instance_pid = start_supervised!({Jido, name: instance, namespace: namespace}, id: instance)
    ref = Ref.new!(namespace: namespace, id: "recovering")
    observer = unique_instance("resolution_observer")
    Process.register(self(), observer)

    agent =
      Jido.Agent.define!(%{
        name: "instance_ref_recovering",
        extensions: [
          %{
            id: ReadyPlugin.id(),
            provider: ReadyPlugin,
            vsn: ReadyPlugin.vsn(),
            data: %{observer: observer}
          }
        ]
      })
      |> Jido.Agent.instantiate!(id: ref.id)

    assert {:ok, server} = Jido.start_agent_ref(instance, ref, agent)
    assert_receive {:ready_gate, gate, _root}, 1_000
    assert Jido.resolve_agent(instance, ref) == {:error, :recovering}
    send(gate, :release)
    assert Jido.AgentServer.await_ready(server) == :ok
    assert Jido.resolve_agent(instance, ref) == {:ok, server}

    :sys.suspend(instance_pid)
    registry = Process.whereis(Jido.registry_name(instance))
    monitor = Process.monitor(registry)

    try do
      Process.exit(registry, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^registry, _reason}, 1_000
      assert Jido.resolve_agent(instance, ref) == {:error, :unavailable}
    after
      :sys.resume(instance_pid)
    end
  end

  @tag obligation: "jido.instance.I8"
  test "Ref routing forwards context and explicit caller waits" do
    namespace = unique_namespace("routing")
    instance = unique_instance("routing")
    start_supervised!({Jido, name: instance, namespace: namespace}, id: instance)
    {:ok, ref} = Jido.agent_ref(instance, "counter")
    {:ok, server} = Jido.start_agent_ref(instance, ref, Counter)

    assert {:error, %Error.ValidationError{}} =
             Jido.call(instance, ref, signal(1), timeout: -1)

    pending =
      Jido.submit(instance, ref, signal(1), context: %{observer: self(), gate: true})

    assert_receive {:add_started, action, context}, 1_000
    assert context.observer == self()
    on_exit(fn -> if Process.alive?(action), do: send(action, :release) end)

    assert catch_exit(Jido.call(instance, ref, signal(1), timeout: 0))

    for read <- [
          &Jido.agent(instance, ref, &1),
          &Jido.status(instance, ref, &1),
          &Jido.plugin_state(instance, ref, StatePlugin, &1),
          &Jido.children(instance, ref, &1),
          &Jido.await_ready(instance, ref, &1)
        ] do
      assert {:error, %Error.ValidationError{}} = read.(-1)
    end

    send(action, :release)
    assert {:ok, committed, []} = Jido.await(pending)
    assert committed.state.count == 1
    assert Jido.AgentServer.agent(server) == committed
  end

  @tag obligation: "jido.instance.I8"
  test "Ref Plugin reads keep the selected Plugin" do
    namespace = unique_namespace("plugin-state")
    instance = unique_instance("plugin-state")
    start_supervised!({Jido, name: instance, namespace: namespace}, id: instance)
    ref = Ref.new!(namespace: namespace, id: "plugin-agent")

    agent =
      Jido.Agent.define!(%{
        name: "instance_ref_plugin_state",
        extensions: [
          %{id: StatePlugin.id(), provider: StatePlugin, vsn: StatePlugin.vsn(), data: %{}}
        ]
      })
      |> Jido.Agent.instantiate!(id: ref.id)

    assert {:ok, _server} = Jido.start_agent_ref(instance, ref, agent)
    assert Jido.await_ready(instance, ref) == :ok
    assert Jido.plugin_state(instance, ref, StatePlugin) == {:ok, 9}
    assert Jido.plugin_state(instance, ref, ReadyPlugin) == {:error, :plugin_not_found}
  end

  @tag obligation: ["jido.instance.I3", "jido.instance.I6", "jido.instance.I8"]
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

    assert {:ok, server} =
             Jido.start_agent_ref(first, ref, Counter,
               persistence: :inherit,
               persistence_mode: :create
             )

    assert :ok = Jido.AgentServer.await_ready(server)

    assert {:ok, agent, _} = Jido.call(first, ref, signal(7))
    assert agent.state.count == 7
    assert :ok = Jido.hibernate_ref(first, ref)
    assert :ok = stop_supervised(first)

    start_supervised!(
      {Jido, name: second, namespace: namespace, persistence: store},
      id: second
    )

    assert {:ok, server} = Jido.activate_agent(second, ref, Counter)
    assert :ok = Jido.AgentServer.await_ready(server)
    assert Jido.agent(second, ref).state.count == 7
    assert {:ok, restored, _} = Jido.call(second, ref, signal(1))
    assert restored.state.count == 8
    assert :ok = Jido.hibernate_ref(second, ref)
    assert :ok = Jido.delete_agent(second, ref, Counter)

    assert {:error, :deleted} =
             Jido.Persistence.load_agent(store, Counter, ref.id,
               namespace: namespace,
               partition: ref.partition
             )

    case Jido.activate_agent(second, ref, Counter) do
      {:ok, deleted} ->
        exit = catch_exit(Jido.AgentServer.await_ready(deleted))

        assert match?({{:shutdown, :deleted}, _}, exit) or
                 match?({:noproc, _}, exit)

      {:error, :worker_unavailable} ->
        assert Jido.whereis_agent(second, ref.id, partition: ref.partition) == nil
    end
  end

  @tag obligation: "jido.instance.I6"
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

  @tag obligation: "jido.instance.I8"
  test "Ref runtime controls preserve their Server results and reject a missing activation" do
    instance = unique_instance("ref-controls")
    start_supervised!({Jido, name: instance, namespace: unique_namespace("ref-controls")})
    {:ok, ref} = Jido.agent_ref(instance, "counter")
    {:ok, server} = Jido.start_agent_ref(instance, ref, Counter)

    assert Jido.cancel(instance, ref) == Jido.AgentServer.cancel(server)

    assert Jido.cancel_turn(instance, ref, "absent") ==
             Jido.AgentServer.cancel_turn(server, "absent")

    assert :ok = Jido.attach(instance, ref)
    assert Jido.AgentServer.status(server).owners == [self()]
    assert :ok = Jido.touch(instance, ref)
    assert :ok = Jido.detach(instance, ref)
    assert Jido.AgentServer.status(server).owners == []

    assert Jido.plugin_state(instance, ref, __MODULE__) ==
             Jido.AgentServer.plugin_state(server, __MODULE__)

    assert {:error, %Error.ValidationError{}} = Jido.hibernate_ref(instance, ref, unknown: true)

    for control <- [
          &Jido.cancel(instance, ref, &1),
          &Jido.cancel_turn(instance, ref, "absent", &1),
          &Jido.attach(instance, ref, self(), &1),
          &Jido.detach(instance, ref, self(), &1)
        ] do
      assert {:error, %Error.ValidationError{}} = control.(-1)
    end

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

  @tag obligation: "jido.instance.I8"
  test "Ref stop forwards the reason and caller timeout" do
    instance = unique_instance("ref-stop")
    start_supervised!({Jido, name: instance, namespace: unique_namespace("ref-stop")})

    {:ok, reason_ref} = Jido.agent_ref(instance, "reason")
    {:ok, reason_server} = Jido.start_agent_ref(instance, reason_ref, Counter)
    reason_monitor = Process.monitor(reason_server)

    assert :ok = Jido.stop_agent_ref(instance, reason_ref, :contract_stop)

    assert_receive {:DOWN, ^reason_monitor, :process, ^reason_server, {:shutdown, :contract_stop}}

    {:ok, timeout_ref} = Jido.agent_ref(instance, "timeout")
    {:ok, timeout_server} = Jido.start_agent_ref(instance, timeout_ref, Counter)
    :ok = :sys.suspend(timeout_server)

    task =
      Task.async(fn ->
        catch_exit(Jido.stop_agent_ref(instance, timeout_ref, :shutdown, 0))
      end)

    try do
      assert {:ok, {:timeout, _}} = Task.yield(task, 500)
    after
      :ok = :sys.resume(timeout_server)

      if Task.yield(task, 100) == nil do
        Task.shutdown(task, :brutal_kill)
      end
    end
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
