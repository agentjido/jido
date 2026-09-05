defmodule JidoTest.InstanceTest do
  use ExUnit.Case, async: false

  import JidoTest.Eventually

  alias Jido.AgentServer, as: Server
  alias Jido.Persistence.Redis

  defmodule TestInstance do
    use Jido, otp_app: :jido_test_instance
  end

  defmodule RedisTestAgent do
    use Jido.Agent,
      name: "redis_test_agent",
      schema: Zoi.object(%{counter: Zoi.integer() |> Zoi.default(0)})
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

          ["EVAL", _script, "1", key, mode, expected, value, _ttl] ->
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
        persistence: {Jido.Persistence.Redis, [
          command_fn: fn command -> JidoTest.InstanceTest.RedisMock.command(command) end,
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
      stop_test_instance()
    end)

    :ok
  end

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

  test "an inline instance keeps its Redis persistence function" do
    module = compile_inline_redis_instance("inline-persistence")
    on_exit(fn -> unload_module(module) end)

    assert {Redis, opts} = module.__jido_persistence__()
    assert is_function(opts[:command_fn], 1)
    assert {:ok, {:echo, ["PING"]}} = opts[:command_fn].(["PING"])
    assert opts[:prefix] == "inline-persistence"
  end

  test "hibernate and thaw work through an instance module" do
    module = compile_inline_redis_instance("inline-persist")
    on_exit(fn -> unload_module(module) end)
    start_supervised!(module)

    agent =
      RedisTestAgent.new!(id: "redis-instance-agent")
      |> then(fn agent -> %{agent | state: %{agent.state | counter: 42}} end)

    assert {:ok, pid} = module.start_agent(agent, restore: false)
    assert :ok = module.hibernate(pid)
    assert {:ok, thawed_pid} = module.thaw(RedisTestAgent, agent.id)
    assert Server.agent(thawed_pid).state.counter == 42
  end

  test "partitioned Agent checkpoints use separate keys" do
    module = compile_inline_redis_instance("inline-partition-persist")
    on_exit(fn -> unload_module(module) end)
    start_supervised!(module)

    agent =
      RedisTestAgent.new!(id: "shared-partition-key")
      |> then(fn agent -> %{agent | state: %{agent.state | counter: 10}} end)

    partitioned = %{agent | state: %{agent.state | counter: 20}}

    assert {:ok, pid} = module.start_agent(agent, restore: false)

    assert {:ok, partitioned_pid} =
             module.start_agent(partitioned, partition: :blue, restore: false)

    assert :ok = module.hibernate(pid)
    assert :ok = module.hibernate(partitioned_pid)

    assert {:ok, restored_pid} = module.thaw(RedisTestAgent, agent.id)

    assert {:ok, restored_partitioned_pid} =
             module.thaw(RedisTestAgent, agent.id, partition: :blue)

    assert Server.agent(restored_pid).state.counter == 10
    assert Server.agent(restored_partitioned_pid).state.counter == 20
  end

  test "starts the Agent runtime supervision tree" do
    {:ok, pid} = TestInstance.start_link()

    assert Process.whereis(TestInstance) == pid
    assert Process.whereis(TestInstance.task_supervisor_name())
    assert Process.whereis(TestInstance.registry_name())
    assert Process.whereis(TestInstance.runtime_store_name())
    assert Process.whereis(TestInstance.agent_supervisor_name())
  end

  test "instance Agent APIs start, find, list, count, and stop Agents" do
    {:ok, _pid} = TestInstance.start_link()

    {:ok, first} = TestInstance.start_agent(RedisTestAgent, id: "agent-1")
    {:ok, second} = TestInstance.start_agent(RedisTestAgent, id: "agent-2")

    assert TestInstance.whereis_agent("agent-1") == first
    assert TestInstance.whereis_agent("missing") == nil

    assert Enum.sort(TestInstance.list_agents()) ==
             Enum.sort([{"agent-1", first}, {"agent-2", second}])

    assert TestInstance.agent_count() == 2

    monitor = Process.monitor(first)
    assert :ok = TestInstance.stop_agent("agent-1")
    assert_receive {:DOWN, ^monitor, :process, ^first, _reason}, 1_000
    eventually(fn -> TestInstance.whereis_agent("agent-1") == nil end)

    assert :ok = TestInstance.stop_agent(second)
    assert TestInstance.agent_count() == 0
  end

  test "partitions isolate equal Agent ids" do
    {:ok, _pid} = TestInstance.start_link()

    {:ok, plain} = TestInstance.start_agent(RedisTestAgent, id: "shared")
    {:ok, blue} = TestInstance.start_agent(RedisTestAgent, id: "shared", partition: :blue)

    assert TestInstance.whereis_agent("shared") == plain
    assert TestInstance.whereis_agent("shared", partition: :blue) == blue
    assert TestInstance.list_agents() == [{"shared", plain}]
    assert TestInstance.list_agents(partition: :blue) == [{"shared", blue}]
  end

  test "works as a child in another Supervisor" do
    {:ok, supervisor} = Supervisor.start_link([TestInstance], strategy: :one_for_one)

    assert Process.alive?(supervisor)
    assert Process.whereis(TestInstance)

    Supervisor.stop(supervisor, :normal, 5_000)
  end
end
