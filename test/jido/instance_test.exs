defmodule JidoTest.InstanceTest do
  use ExUnit.Case, async: false

  import JidoTest.Eventually

  alias Jido.Storage.Redis
  alias Jido.Thread
  alias JidoTest.TestAgents.Minimal

  defmodule TestInstance do
    use Jido, otp_app: :jido_test_instance
  end

  defmodule RedisTestAgent do
    use Jido.Agent,
      name: "redis_test_agent",
      schema: [
        counter: [type: :integer, default: 0]
      ]

    @impl true
    def signal_routes(_ctx), do: []
  end

  defmodule RedisMock do
    def child_spec(opts) do
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, [opts]}
      }
    end

    def start_link(_opts \\ []) do
      Agent.start_link(fn -> %{} end, name: __MODULE__)
    end

    def command(command) do
      Agent.get_and_update(__MODULE__, fn state ->
        case command do
          ["GET", key] ->
            {{:ok, Map.get(state, key)}, state}

          ["SET", key, value] ->
            {{:ok, "OK"}, Map.put(state, key, value)}

          ["SET", key, value, "PX", _ttl] ->
            {{:ok, "OK"}, Map.put(state, key, value)}

          ["DEL" | keys] ->
            deleted = Enum.count(keys, &Map.has_key?(state, &1))
            {{:ok, deleted}, Map.drop(state, keys)}

          _ ->
            {{:ok, {:echo, command}}, state}
        end
      end)
    end
  end

  defp compile_inline_redis_instance(prefix) do
    module =
      Module.concat(__MODULE__, :"InlineRedisInstance#{System.unique_integer([:positive])}")

    source = """
    defmodule #{inspect(module)} do
      use Jido,
        otp_app: :jido_test_instance,
        storage: {Jido.Storage.Redis, [
          command_fn: fn cmd -> JidoTest.InstanceTest.RedisMock.command(cmd) end,
          prefix: #{inspect(prefix)}
        ]}
    end
    """

    Code.compile_string(source)
    module
  end

  defp unload_module(module) do
    :code.purge(module)
    :code.delete(module)
  end

  setup do
    Application.put_env(:jido_test_instance, TestInstance, max_tasks: 500)
    {:ok, _pid} = start_supervised({RedisMock, []})

    on_exit(fn ->
      Application.delete_env(:jido_test_instance, TestInstance)

      if pid = Process.whereis(TestInstance) do
        try do
          Supervisor.stop(pid, :normal, 5000)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    :ok
  end

  describe "instance module definition" do
    test "generates child_spec/1" do
      spec = TestInstance.child_spec([])

      assert spec.id == TestInstance
      assert spec.type == :supervisor
      assert {Jido, :start_link, [opts]} = spec.start
      assert Keyword.get(opts, :name) == TestInstance
    end

    test "generates config/1 that reads from application env" do
      config = TestInstance.config()

      assert Keyword.get(config, :max_tasks) == 500
    end

    test "config/1 merges runtime overrides" do
      config = TestInstance.config(max_tasks: 1000, extra: :value)

      assert Keyword.get(config, :max_tasks) == 1000
      assert Keyword.get(config, :extra) == :value
    end

    test "child_spec/1 accepts runtime overrides" do
      spec = TestInstance.child_spec(max_tasks: 2000)

      assert {Jido, :start_link, [opts]} = spec.start
      assert Keyword.get(opts, :max_tasks) == 2000
    end

    test "supports anonymous Redis command_fn in __jido_storage__/0" do
      module = compile_inline_redis_instance("inline-storage")
      on_exit(fn -> unload_module(module) end)

      assert {Redis, opts} = module.__jido_storage__()
      assert is_function(opts[:command_fn], 1)
      assert {:ok, {:echo, ["PING"]}} = opts[:command_fn].(["PING"])
      assert opts[:prefix] == "inline-storage"
    end

    test "hibernate and thaw work through a dynamically compiled Redis instance" do
      module = compile_inline_redis_instance("inline-persist")
      on_exit(fn -> unload_module(module) end)

      agent =
        RedisTestAgent.new(id: "redis-instance-agent")
        |> then(fn agent -> %{agent | state: %{agent.state | counter: 42}} end)
        |> then(fn agent ->
          thread =
            Thread.new(id: "redis-thread")
            |> Thread.append(%{kind: :note, payload: %{text: "saved"}})

          %{agent | state: Map.put(agent.state, :__thread__, thread)}
        end)

      assert :ok = module.hibernate(agent)
      assert {:ok, thawed} = module.thaw(RedisTestAgent, "redis-instance-agent")
      assert thawed.state.counter == 42
      assert thawed.state[:__thread__].id == "redis-thread"
      assert Thread.entry_count(thawed.state[:__thread__]) == 1
    end
  end

  describe "instance lifecycle" do
    test "start_link/1 starts the supervisor" do
      {:ok, pid} = TestInstance.start_link()

      assert is_pid(pid)
      assert Process.alive?(pid)
      assert Process.whereis(TestInstance) == pid
    end

    test "starts TaskSupervisor as child" do
      {:ok, _pid} = TestInstance.start_link()

      task_sup = TestInstance.task_supervisor_name()
      assert Process.whereis(task_sup) != nil
    end

    test "starts Registry as child" do
      {:ok, _pid} = TestInstance.start_link()

      reg = TestInstance.registry_name()
      assert Process.whereis(reg) != nil
    end

    test "starts RuntimeStore as child" do
      {:ok, _pid} = TestInstance.start_link()

      runtime_store = TestInstance.runtime_store_name()
      assert Process.whereis(runtime_store) != nil
    end

    test "starts AgentSupervisor as child" do
      {:ok, _pid} = TestInstance.start_link()

      agent_sup = TestInstance.agent_supervisor_name()
      assert Process.whereis(agent_sup) != nil
    end
  end

  describe "instance agent API" do
    test "start_agent/2 starts an agent" do
      {:ok, _sup_pid} = TestInstance.start_link()

      {:ok, agent_pid} = TestInstance.start_agent(Minimal, id: "test-1")

      assert is_pid(agent_pid)
      assert Process.alive?(agent_pid)
    end

    test "whereis/1 looks up an agent by ID" do
      {:ok, _sup_pid} = TestInstance.start_link()

      {:ok, agent_pid} = TestInstance.start_agent(Minimal, id: "lookup-test")

      found_pid = TestInstance.whereis("lookup-test")
      assert found_pid == agent_pid
    end

    test "whereis/1 returns nil for unknown ID" do
      {:ok, _sup_pid} = TestInstance.start_link()

      assert TestInstance.whereis("nonexistent") == nil
    end

    test "list_agents/0 lists all agents" do
      {:ok, _sup_pid} = TestInstance.start_link()

      {:ok, _} = TestInstance.start_agent(Minimal, id: "list-1")
      {:ok, _} = TestInstance.start_agent(Minimal, id: "list-2")

      agents = TestInstance.list_agents()
      ids = Enum.map(agents, fn {id, _pid} -> id end)

      assert "list-1" in ids
      assert "list-2" in ids
    end

    test "agent_count/0 returns count of running agents" do
      {:ok, _sup_pid} = TestInstance.start_link()

      assert TestInstance.agent_count() == 0

      {:ok, _} = TestInstance.start_agent(Minimal, id: "count-1")
      assert TestInstance.agent_count() == 1

      {:ok, _} = TestInstance.start_agent(Minimal, id: "count-2")
      assert TestInstance.agent_count() == 2
    end

    test "stop_agent/1 stops an agent by ID" do
      {:ok, _sup_pid} = TestInstance.start_link()

      {:ok, pid} = TestInstance.start_agent(Minimal, id: "stop-test")

      assert TestInstance.whereis("stop-test") != nil
      # Monitor before stopping to ensure we catch the DOWN
      ref = Process.monitor(pid)
      assert :ok = TestInstance.stop_agent("stop-test")
      # Wait for the process to actually terminate
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1000
      # Use eventually to wait for registry to update
      eventually(fn -> TestInstance.whereis("stop-test") == nil end)
    end

    test "stop_agent/1 stops an agent by pid" do
      {:ok, _sup_pid} = TestInstance.start_link()

      {:ok, pid} = TestInstance.start_agent(Minimal, id: "stop-pid-test")

      assert Process.alive?(pid)
      assert :ok = TestInstance.stop_agent(pid)
      refute Process.alive?(pid)
    end
  end

  describe "supervision tree integration" do
    test "can be used in Supervisor.start_link/2" do
      children = [TestInstance]

      {:ok, sup_pid} = Supervisor.start_link(children, strategy: :one_for_one)

      assert Process.alive?(sup_pid)
      assert Process.whereis(TestInstance) != nil

      Supervisor.stop(sup_pid, :normal, 5000)
    end

    test "can be used with runtime options in supervision tree" do
      children = [{TestInstance, max_tasks: 3000}]

      {:ok, sup_pid} = Supervisor.start_link(children, strategy: :one_for_one)

      assert Process.alive?(sup_pid)
      assert Process.whereis(TestInstance) != nil

      Supervisor.stop(sup_pid, :normal, 5000)
    end
  end
end
