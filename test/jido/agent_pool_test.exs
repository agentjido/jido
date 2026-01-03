defmodule JidoTest.AgentPoolTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Jido.AgentPool
  alias Jido.AgentServer
  alias Jido.Signal
  alias JidoTest.WaitHelpers

  defmodule IncrementAction do
    @moduledoc false
    use Jido.Action, name: "increment", schema: []

    def run(_params, context) do
      count = Map.get(context.state, :counter, 0)
      {:ok, %{counter: count + 1}}
    end
  end

  defmodule GetCountAction do
    @moduledoc false
    use Jido.Action, name: "get_count", schema: []

    def run(_params, context) do
      {:ok, %{last_count: Map.get(context.state, :counter, 0)}}
    end
  end

  defmodule PoolTestAgent do
    @moduledoc false
    use Jido.Agent,
      name: "pool_test_agent",
      schema: [
        counter: [type: :integer, default: 0],
        last_count: [type: :integer, default: 0]
      ]

    def signal_routes do
      [
        {"increment", IncrementAction},
        {"get_count", GetCountAction}
      ]
    end
  end

  defp unique_jido_name do
    :"jido_pool_test_#{System.unique_integer([:positive])}"
  end

  describe "pool configuration" do
    test "starts pool with Jido instance" do
      jido_name = unique_jido_name()

      {:ok, jido_pid} =
        Jido.start_link(
          name: jido_name,
          agent_pools: [
            {:test_pool, PoolTestAgent, size: 2, max_overflow: 0}
          ]
        )

      pool_name = Jido.agent_pool_name(jido_name, :test_pool)
      assert Process.whereis(pool_name) != nil

      Supervisor.stop(jido_pid)
    end

    test "multiple pools can be configured" do
      jido_name = unique_jido_name()

      {:ok, jido_pid} =
        Jido.start_link(
          name: jido_name,
          agent_pools: [
            {:pool_a, PoolTestAgent, size: 2},
            {:pool_b, PoolTestAgent, size: 3}
          ]
        )

      assert Process.whereis(Jido.agent_pool_name(jido_name, :pool_a)) != nil
      assert Process.whereis(Jido.agent_pool_name(jido_name, :pool_b)) != nil

      Supervisor.stop(jido_pid)
    end
  end

  describe "with_agent/4" do
    test "executes function with pooled agent" do
      jido_name = unique_jido_name()

      {:ok, jido_pid} =
        Jido.start_link(
          name: jido_name,
          agent_pools: [
            {:test_pool, PoolTestAgent, size: 2}
          ]
        )

      result =
        AgentPool.with_agent(jido_name, :test_pool, fn pid ->
          assert is_pid(pid)
          :worked
        end)

      assert result == :worked

      Supervisor.stop(jido_pid)
    end

    test "can call agent within transaction" do
      jido_name = unique_jido_name()

      {:ok, jido_pid} =
        Jido.start_link(
          name: jido_name,
          agent_pools: [
            {:test_pool, PoolTestAgent, size: 2}
          ]
        )

      signal = Signal.new!("increment", %{}, source: "/test")

      result =
        AgentPool.with_agent(jido_name, :test_pool, fn pid ->
          {:ok, agent} = AgentServer.call(pid, signal)
          agent.state.counter
        end)

      assert result == 1

      Supervisor.stop(jido_pid)
    end

    test "agent state persists across calls" do
      jido_name = unique_jido_name()

      {:ok, jido_pid} =
        Jido.start_link(
          name: jido_name,
          agent_pools: [
            {:test_pool, PoolTestAgent, size: 1}
          ]
        )

      signal = Signal.new!("increment", %{}, source: "/test")

      AgentPool.with_agent(jido_name, :test_pool, fn pid ->
        AgentServer.call(pid, signal)
      end)

      result =
        AgentPool.with_agent(jido_name, :test_pool, fn pid ->
          {:ok, agent} = AgentServer.call(pid, signal)
          agent.state.counter
        end)

      assert result == 2

      Supervisor.stop(jido_pid)
    end
  end

  describe "call/4" do
    test "sends signal to pooled agent" do
      jido_name = unique_jido_name()

      {:ok, jido_pid} =
        Jido.start_link(
          name: jido_name,
          agent_pools: [
            {:test_pool, PoolTestAgent, size: 2}
          ]
        )

      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, agent} = AgentPool.call(jido_name, :test_pool, signal)

      assert agent.state.counter == 1

      Supervisor.stop(jido_pid)
    end
  end

  describe "cast/4" do
    test "sends async signal to pooled agent" do
      jido_name = unique_jido_name()

      {:ok, jido_pid} =
        Jido.start_link(
          name: jido_name,
          agent_pools: [
            {:test_pool, PoolTestAgent, size: 1}
          ]
        )

      signal = Signal.new!("increment", %{}, source: "/test")
      assert :ok = AgentPool.cast(jido_name, :test_pool, signal)

      WaitHelpers.wait_until(
        fn ->
          get_signal = Signal.new!("get_count", %{}, source: "/test")

          case AgentPool.call(jido_name, :test_pool, get_signal) do
            {:ok, agent} -> agent.state.counter >= 1
            _ -> false
          end
        end,
        label: "pooled agent to process cast"
      )

      get_signal = Signal.new!("get_count", %{}, source: "/test")
      {:ok, agent} = AgentPool.call(jido_name, :test_pool, get_signal)
      assert agent.state.counter >= 1

      Supervisor.stop(jido_pid)
    end
  end

  describe "status/2" do
    test "returns pool status" do
      jido_name = unique_jido_name()

      {:ok, jido_pid} =
        Jido.start_link(
          name: jido_name,
          agent_pools: [
            {:test_pool, PoolTestAgent, size: 3, max_overflow: 2}
          ]
        )

      status = AgentPool.status(jido_name, :test_pool)

      assert status.state == :ready
      assert status.overflow == 0
      assert status.available == 3
      assert status.checked_out == 0

      Supervisor.stop(jido_pid)
    end

    test "shows checked out workers" do
      jido_name = unique_jido_name()

      {:ok, jido_pid} =
        Jido.start_link(
          name: jido_name,
          agent_pools: [
            {:test_pool, PoolTestAgent, size: 3}
          ]
        )

      pid = AgentPool.checkout(jido_name, :test_pool)

      status = AgentPool.status(jido_name, :test_pool)
      assert status.checked_out == 1

      AgentPool.checkin(jido_name, :test_pool, pid)

      status = AgentPool.status(jido_name, :test_pool)
      assert status.checked_out == 0

      Supervisor.stop(jido_pid)
    end
  end

  describe "checkout/3 and checkin/3" do
    test "manual checkout and checkin" do
      jido_name = unique_jido_name()

      {:ok, jido_pid} =
        Jido.start_link(
          name: jido_name,
          agent_pools: [
            {:test_pool, PoolTestAgent, size: 2}
          ]
        )

      pid = AgentPool.checkout(jido_name, :test_pool)
      assert is_pid(pid)

      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      assert :ok = AgentPool.checkin(jido_name, :test_pool, pid)

      Supervisor.stop(jido_pid)
    end
  end

  describe "worker_opts" do
    test "passes worker_opts to agent server" do
      jido_name = unique_jido_name()

      {:ok, jido_pid} =
        Jido.start_link(
          name: jido_name,
          agent_pools: [
            {:test_pool, PoolTestAgent, size: 1, worker_opts: [initial_state: %{counter: 100}]}
          ]
        )

      get_signal = Signal.new!("get_count", %{}, source: "/test")
      {:ok, agent} = AgentPool.call(jido_name, :test_pool, get_signal)

      assert agent.state.counter == 100

      Supervisor.stop(jido_pid)
    end
  end

  describe "concurrent access" do
    test "handles concurrent requests" do
      jido_name = unique_jido_name()

      {:ok, jido_pid} =
        Jido.start_link(
          name: jido_name,
          agent_pools: [
            {:test_pool, PoolTestAgent, size: 4}
          ]
        )

      signal = Signal.new!("increment", %{}, source: "/test")

      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            AgentPool.call(jido_name, :test_pool, signal)
          end)
        end

      results = Task.await_many(tasks)

      assert Enum.all?(results, fn {:ok, _agent} -> true end)

      Supervisor.stop(jido_pid)
    end
  end
end
