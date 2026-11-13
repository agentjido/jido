defmodule Jido.Instance.ContractTest do
  use ExUnit.Case, async: false
  use Covenant.Case, component: "jido.instance", async: false

  setup :ensure_namespace_registry

  import Jido.Test.Eventually

  alias Jido.AgentServer, as: Server
  alias Jido.Persistence.Redis

  defp ensure_namespace_registry(context),
    do: Jido.Test.Instance.ContractSupport.ensure_namespace_registry(context)

  defmodule TestInstance do
    use Jido, otp_app: :jido_test_instance, namespace: "instance-test"
  end

  defmodule RedisTestAgent do
    use Jido.Agent, name: "redis_test_agent"

    state do
      schema Jido.Joi.object(%{counter: Jido.Joi.integer() |> Jido.Joi.default(0)})
    end
  end

  defmodule RedisMock do
    def child_spec(opts) do
      %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}
    end

    def start_link(_opts \\ []), do: Elixir.Agent.start_link(fn -> %{} end, name: __MODULE__)

    def command(command) do
      Elixir.Agent.get_and_update(__MODULE__, fn state ->
        case command do
          ["GET", key] ->
            {{:ok, Map.get(state, key)}, state}

          ["SET", key, value] ->
            {{:ok, "OK"}, Map.put(state, key, value)}

          ["SET", key, value, "PX", _ttl] ->
            {{:ok, "OK"}, Map.put(state, key, value)}

          ["EVAL", _script, "1", key, mode, expected, value] ->
            matches? =
              case mode do
                "missing" -> not Map.has_key?(state, key)
                "value" -> Map.get(state, key) == expected
              end

            if matches?,
              do: {{:ok, 1}, Map.put(state, key, value)},
              else: {{:ok, 0}, state}

          ["DEL" | keys] ->
            deleted = Enum.count(keys, &Map.has_key?(state, &1))
            {{:ok, deleted}, Map.drop(state, keys)}

          _other ->
            {{:ok, {:echo, command}}, state}
        end
      end)
    end
  end

  defp compile_inline_redis_instance(prefix) do
    module =
      Module.concat(__MODULE__, :"InlineRedisInstance#{System.unique_integer([:positive])}")

    Code.compile_string("""
    defmodule #{inspect(module)} do
      use Jido,
        otp_app: :jido_test_instance,
        namespace: #{inspect(prefix)},
        persistence: {Jido.Persistence.Redis, [
          command_fn: fn command -> Jido.Instance.ContractTest.RedisMock.command(command) end,
          prefix: #{inspect(prefix)}
        ]}
    end
    """)

    module
  end

  defp unload_module(module) do
    :code.purge(module)
    :code.delete(module)
  end

  defp stop_test_instance do
    if pid = Process.whereis(TestInstance) do
      try do
        Supervisor.stop(pid, :normal, 5_000)
      catch
        :exit, _reason -> :ok
      end
    end

    :ok
  end

  setup do
    stop_test_instance()
    Application.put_env(:jido_test_instance, TestInstance, max_tasks: 500)
    {:ok, _pid} = start_supervised({RedisMock, []})

    on_exit(fn ->
      Application.delete_env(:jido_test_instance, TestInstance)
      Jido.Telemetry.set_debug(TestInstance, :off)
      stop_test_instance()
    end)

    :ok
  end

  @tag obligation: ["jido.instance.I1", "jido.instance.I2"]
  test "instance module exposes configuration and a child specification" do
    assert TestInstance.config()[:max_tasks] == 500
    assert TestInstance.config(max_tasks: 1_000)[:max_tasks] == 1_000

    spec = TestInstance.child_spec(max_tasks: 2_000)
    assert spec.id == TestInstance
    assert spec.type == :supervisor
    assert {Jido, :start_link, [opts]} = spec.start
    assert opts[:name] == TestInstance
    assert opts[:max_tasks] == 2_000
  end

  @tag obligation: "jido.instance.I1"
  test "use Jido rejects invalid definition options" do
    cases = [
      {"missing", ~s(namespace: "missing")},
      {"unknown", ~s(otp_app: :jido, unknown: true)},
      {"duplicate", ~s(otp_app: :jido, namespace: "first", namespace: "second")}
    ]

    for {label, options} <- cases do
      module =
        Module.concat(
          __MODULE__,
          :"InvalidDefinition#{label}#{System.unique_integer([:positive])}"
        )

      error =
        assert_raise Jido.Error.ValidationError, fn ->
          Code.compile_string("""
          defmodule #{inspect(module)} do
            use Jido, #{options}
          end
          """)
        end

      assert Jido.Error.code(error) == :jido_instance_invalid_config
    end
  end

  @tag obligation: "jido.instance.I1"
  test "use Jido accepts compile-time application and namespace attributes" do
    module =
      Module.concat(__MODULE__, :"AttributeDefinition#{System.unique_integer([:positive])}")

    namespace = "jido/test/attribute-definition/#{System.unique_integer([:positive])}"

    Code.compile_string("""
    defmodule #{inspect(module)} do
      @app :jido
      @namespace #{inspect(namespace)}
      use Jido, otp_app: @app, namespace: @namespace
    end
    """)

    on_exit(fn -> unload_module(module) end)

    assert %{start: {Jido, :start_link, [opts]}} = module.child_spec()
    assert opts[:otp_app] == :jido
    assert opts[:namespace] == namespace
  end

  @tag obligation: ["jido.instance.I1", "jido.instance.I4"]
  test "generated modules expose only the required configuration hook" do
    assert function_exported?(TestInstance, :__jido_persistence__, 0)
    refute function_exported?(TestInstance, :__otp_app__, 0)
    refute function_exported?(TestInstance, :__jido_namespace__, 0)
  end

  @tag obligation: "jido.instance.I1"
  test "instance module keeps its module name when runtime options include another name" do
    other_name = Module.concat(TestInstance, Other)
    spec = TestInstance.child_spec(name: other_name)

    assert spec.id == TestInstance
    assert {Jido, :start_link, [opts]} = spec.start
    assert opts[:name] == TestInstance
  end

  @tag obligation: ["jido.instance.I1", "jido.instance.I4"]
  test "runtime debug options override application configuration" do
    Application.put_env(:jido_test_instance, TestInstance, max_tasks: 500, debug: true)
    assert {:ok, _pid} = TestInstance.start_link(debug: false)
    assert Jido.Telemetry.debug_level(TestInstance) == :off

    stop_test_instance()
    assert {:ok, _pid} = TestInstance.start_link(debug: :verbose)
    assert Jido.Telemetry.debug_level(TestInstance) == :verbose
  end

  @tag obligation: "jido.instance.I1"
  test "invalid application instance configuration reaches the final validator" do
    Application.put_env(:jido_test_instance, TestInstance, :invalid)

    assert {:error, %{__exception__: true} = error} = TestInstance.start_link()
    assert Jido.Error.code(error) == :jido_instance_invalid_config
    assert Process.whereis(TestInstance) == nil
  end

  @tag obligation: "jido.instance.I4"
  test "an inline instance keeps its Redis persistence function" do
    module = compile_inline_redis_instance("inline-persistence")
    on_exit(fn -> unload_module(module) end)

    assert %Jido.Persistence.Config{store: {Redis, opts}, codec: Jido.Persistence.Codec.Term} =
             module.__jido_persistence__()

    assert is_function(opts[:command_fn], 1)
    assert {:ok, {:echo, ["PING"]}} = opts[:command_fn].(["PING"])
    assert opts[:prefix] == "inline-persistence"
  end

  @tag obligation: "jido.instance.I4"
  test "application and start options replace the declared persistence default" do
    application_persistence =
      {Jido.Persistence.ETS, table: String.to_atom("jido_app_persistence_#{System.unique_integer([:positive])}")}

    runtime_persistence =
      {Jido.Persistence.ETS, table: String.to_atom("jido_runtime_persistence_#{System.unique_integer([:positive])}")}

    Application.put_env(
      :jido_test_instance,
      TestInstance,
      max_tasks: 500,
      persistence: application_persistence
    )

    {:ok, _pid} = TestInstance.start_link(persistence: runtime_persistence)

    assert %Jido.Persistence.Config{store: ^runtime_persistence} =
             Jido.Instance.RuntimeStore.instance_persistence(TestInstance)

    assert {:ok, %Jido.Persistence.Config{store: ^runtime_persistence}} =
             Jido.Persistence.resolve_config(:inherit, TestInstance)

    agent = RedisTestAgent.instantiate!(id: "configured-persistence")

    assert {:ok, server} =
             Jido.start_agent(TestInstance, agent, persistence_mode: :create)

    assert :ok = Server.await_ready(server)
    assert {:ok, %Jido.AgentServer.Snapshot{}} = Server.stop(server)

    assert {:ok, ^agent} =
             Jido.Persistence.load_agent(runtime_persistence, RedisTestAgent, agent.id, instance: TestInstance)

    stop_test_instance()
    {:ok, _pid} = TestInstance.start_link()

    assert %Jido.Persistence.Config{store: ^application_persistence} =
             Jido.Instance.RuntimeStore.instance_persistence(TestInstance)

    assert {:ok, %Jido.Persistence.Config{store: ^application_persistence}} =
             Jido.Persistence.resolve_config(:inherit, TestInstance)
  end

  @tag obligation: "jido.instance.I4"
  test "a persistent instance rejects a per-Agent Store override" do
    instance_store =
      {Jido.Persistence.ETS, table: String.to_atom("jido_instance_store_#{System.unique_integer([:positive])}")}

    other_store =
      {Jido.Persistence.ETS, table: String.to_atom("jido_agent_store_#{System.unique_integer([:positive])}")}

    {:ok, _pid} = TestInstance.start_link(persistence: instance_store)

    assert {:error, %Jido.Error.ValidationError{message: "Per-Agent persistence is not supported"}} =
             Jido.start_agent(TestInstance, RedisTestAgent,
               id: "override-rejected",
               persistence: other_store
             )

    assert Jido.whereis_agent(TestInstance, "override-rejected") == nil
  end

  @tag obligation: ["jido.instance.I4", "jido.instance.I5"]
  test "stop and thaw use the selected instance" do
    module = compile_inline_redis_instance("inline-persist")
    on_exit(fn -> unload_module(module) end)
    start_supervised!(module)

    agent =
      RedisTestAgent.instantiate!(id: "redis-instance-agent")
      |> then(fn agent -> %{agent | state: %{agent.state | counter: 42}} end)

    assert {:ok, pid} =
             Jido.start_agent(module, agent, persistence: :inherit, persistence_mode: :create)

    assert :ok = Server.await_ready(pid)
    assert {:ok, %Jido.AgentServer.Snapshot{}} = Server.stop(pid)
    assert {:ok, thawed_pid} = Jido.thaw(module, RedisTestAgent, agent.id)
    assert :ok = Server.await_ready(thawed_pid)
    assert Server.snapshot(thawed_pid).agent.state.counter == 42
  end

  @tag obligation: "jido.instance.I5"
  test "partitioned Agent checkpoints use separate keys" do
    module = compile_inline_redis_instance("inline-partition-persist")
    on_exit(fn -> unload_module(module) end)
    start_supervised!(module)

    agent =
      RedisTestAgent.instantiate!(id: "shared-partition-key")
      |> then(fn agent -> %{agent | state: %{agent.state | counter: 10}} end)

    partitioned = %{agent | state: %{agent.state | counter: 20}}

    assert {:ok, pid} =
             Jido.start_agent(module, agent, persistence: :inherit, persistence_mode: :create)

    assert {:ok, partitioned_pid} =
             Jido.start_agent(module, partitioned,
               partition: "blue",
               persistence: :inherit,
               persistence_mode: :create
             )

    assert :ok = Server.await_ready(pid)
    assert {:ok, %Jido.AgentServer.Snapshot{}} = Server.stop(pid)
    assert :ok = Server.await_ready(partitioned_pid)
    assert {:ok, %Jido.AgentServer.Snapshot{}} = Server.stop(partitioned_pid)

    assert {:ok, restored_pid} = Jido.thaw(module, RedisTestAgent, agent.id)

    assert {:ok, restored_partitioned_pid} =
             Jido.thaw(module, RedisTestAgent, agent.id, partition: "blue")

    assert :ok = Server.await_ready(restored_pid)
    assert :ok = Server.await_ready(restored_partitioned_pid)
    assert Server.snapshot(restored_pid).agent.state.counter == 10
    assert Server.snapshot(restored_partitioned_pid).agent.state.counter == 20
  end

  @tag obligation: "jido.instance.I2"
  test "starts the Agent runtime supervision tree" do
    {:ok, pid} = TestInstance.start_link()

    assert Process.whereis(TestInstance) == pid
    assert Process.whereis(Jido.Instance.Names.task_supervisor(TestInstance))
    assert Process.whereis(Jido.Instance.Names.registry(TestInstance))
    assert Process.whereis(Jido.Instance.Names.runtime_store(TestInstance))
    assert Process.whereis(Jido.Instance.Names.agent_supervisor(TestInstance))
  end

  @tag obligation: "jido.instance.I5"
  test "Jido starts, finds, lists, counts, and stops Agents in one instance" do
    {:ok, _pid} = TestInstance.start_link()

    {:ok, first} = Jido.start_agent(TestInstance, RedisTestAgent, id: "agent-1")
    {:ok, second} = Jido.start_agent(TestInstance, RedisTestAgent, id: "agent-2")

    assert Jido.whereis_agent(TestInstance, "agent-1") == first
    assert Jido.whereis_agent(TestInstance, "missing") == nil

    assert Enum.sort(Jido.list_agents(TestInstance)) ==
             Enum.sort([{"agent-1", first}, {"agent-2", second}])

    assert Jido.resident_agent_count(TestInstance) == 2

    monitor = Process.monitor(first)
    assert :ok = Jido.stop_agent(TestInstance, "agent-1")
    assert_receive {:DOWN, ^monitor, :process, ^first, _reason}, 1_000
    eventually(fn -> Jido.whereis_agent(TestInstance, "agent-1") == nil end)

    assert :ok = Jido.stop_agent(TestInstance, second)
    assert Jido.resident_agent_count(TestInstance) == 0
  end

  @tag obligation: "jido.instance.I5"
  test "partitions isolate equal Agent ids" do
    {:ok, _pid} = TestInstance.start_link()

    {:ok, plain} = Jido.start_agent(TestInstance, RedisTestAgent, id: "shared")
    {:ok, blue} = Jido.start_agent(TestInstance, RedisTestAgent, id: "shared", partition: "blue")

    assert Jido.whereis_agent(TestInstance, "shared") == plain
    assert Jido.whereis_agent(TestInstance, "shared", partition: "blue") == blue
    assert Jido.list_agents(TestInstance) == [{"shared", plain}]
    assert Jido.list_agents(TestInstance, partition: "blue") == [{"shared", blue}]
  end

  @tag obligation: "jido.instance.I5"
  test "PID stop requires the exact explicit partition" do
    start_supervised!(TestInstance)
    {:ok, server} = Jido.start_agent(TestInstance, RedisTestAgent, id: "numeric", partition: "1")
    before = Jido.Test.AgentServer.Assertions.committed(server)

    assert Jido.whereis_agent(TestInstance, "numeric", partition: "1") == server
    assert Jido.whereis_agent(TestInstance, "numeric", partition: "1.0") == nil
    assert {:error, :not_found} = Jido.stop_agent(TestInstance, server, partition: "1.0")
    assert Jido.Test.AgentServer.Assertions.committed(server) === before
    assert Jido.whereis_agent(TestInstance, "numeric", partition: "1") == server

    monitor = Process.monitor(server)
    assert :ok = Jido.stop_agent(TestInstance, server, partition: "1")
    assert_receive {:DOWN, ^monitor, :process, ^server, _reason}, 1_000
    assert Jido.whereis_agent(TestInstance, "numeric", partition: "1") == nil
  end

  @tag obligation: "jido.instance.I2"
  test "works as a child in another Supervisor" do
    {:ok, supervisor} = Supervisor.start_link([TestInstance], strategy: :one_for_one)

    assert Process.alive?(supervisor)
    assert Process.whereis(TestInstance)

    Supervisor.stop(supervisor, :normal, 5_000)
  end

  @tag obligation: "jido.instance.I3"
  test "namespace bindings survive a namespace registry worker restart" do
    namespace = "jido/test/registry-restart/#{System.unique_integer([:positive])}"
    instance = String.to_atom("jido_registry_restart_#{System.unique_integer([:positive])}")
    other = String.to_atom("jido_registry_duplicate_#{System.unique_integer([:positive])}")

    instance_pid = start_supervised!({Jido, name: instance, namespace: namespace}, id: instance)
    assert Jido.Instance.NamespaceRegistry.namespace(instance) == namespace

    assert :ok =
             Supervisor.terminate_child(Jido.Supervisor, Jido.Instance.NamespaceRegistry)

    assert {:ok, _registry_pid} =
             Supervisor.restart_child(Jido.Supervisor, Jido.Instance.NamespaceRegistry)

    assert Jido.Instance.NamespaceRegistry.namespace(instance) == namespace
    assert Jido.Instance.NamespaceRegistry.lookup(namespace) == {instance, instance_pid}

    assert {:error, %{__exception__: true} = error} =
             Jido.start_link(name: other, namespace: namespace)

    assert Jido.Error.code(error) == :jido_namespace_already_bound
  end

  @tag obligation: "jido.instance.I4"
  test "a plain instance persistence default survives a runtime store worker restart" do
    instance = String.to_atom("jido_persistence_default_#{System.unique_integer([:positive])}")
    table = String.to_atom("jido_persistence_table_#{System.unique_integer([:positive])}")
    persistence = {Jido.Persistence.ETS, table: table}

    instance_pid =
      start_supervised!(
        {Jido, name: instance, namespace: "test/runtime-store/#{instance}", persistence: persistence},
        id: instance
      )

    runtime_store = Jido.Instance.Names.runtime_store(instance)

    assert %Jido.Persistence.Config{store: ^persistence} =
             Jido.Instance.RuntimeStore.instance_persistence(instance)

    assert :ok = Supervisor.terminate_child(instance_pid, runtime_store)

    assert %Jido.Persistence.Config{store: ^persistence} =
             Jido.Instance.RuntimeStore.instance_persistence(instance)

    assert {:ok, _runtime_store_pid} = Supervisor.restart_child(instance_pid, runtime_store)

    assert %Jido.Persistence.Config{store: ^persistence} =
             Jido.Instance.RuntimeStore.instance_persistence(instance)
  end
end
