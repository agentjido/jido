defmodule JidoTest.AwaitTest do
  use JidoTest.Case, async: false

  alias Jido.AgentServer
  alias Jido.Await
  alias Jido.Signal

  defmodule CompletingAction do
    @moduledoc false
    use Jido.Action, name: "completing_action", schema: []

    def run(_params, _context) do
      {:ok, %{status: :completed, last_answer: "done"}}
    end
  end

  defmodule FailingAction do
    @moduledoc false
    use Jido.Action, name: "failing_action", schema: []

    def run(_params, _context) do
      {:ok, %{status: :failed, error: :test_error}}
    end
  end

  defmodule SlowAction do
    @moduledoc false
    use Jido.Action, name: "slow_action", schema: []

    def run(_params, _context) do
      Process.sleep(100)
      {:ok, %{status: :completed, last_answer: "slow_done"}}
    end
  end

  defmodule SpawnChildAction do
    @moduledoc false
    use Jido.Action, name: "spawn_child", schema: []

    def run(%{tag: tag, child_module: child_module}, _context) do
      directive = %Jido.Agent.Directive.SpawnAgent{
        agent: child_module,
        tag: tag,
        opts: %{id: "child-#{tag}"}
      }

      {:ok, %{}, [directive]}
    end
  end

  defmodule AwaitAgent do
    @moduledoc false
    use Jido.Agent,
      name: "await_agent",
      schema: [
        status: [type: :atom, default: :idle],
        last_answer: [type: :any, default: nil],
        error: [type: :any, default: nil]
      ]

    def signal_routes(_ctx) do
      [
        {"complete", CompletingAction},
        {"fail", FailingAction},
        {"slow", SlowAction},
        {"spawn_child", SpawnChildAction}
      ]
    end
  end

  defmodule ChildAgent do
    @moduledoc false
    use Jido.Agent,
      name: "child_agent",
      schema: [
        status: [type: :atom, default: :idle],
        last_answer: [type: :any, default: nil]
      ]

    def signal_routes(_ctx) do
      [{"complete", CompletingAction}]
    end
  end

  describe "completion/3" do
    test "waits for agent to complete", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: AwaitAgent, id: "await-complete", jido: jido)

      signal = Signal.new!("complete", %{}, source: "/test")
      AgentServer.cast(pid, signal)

      result = Await.completion(pid, 1000)
      assert {:ok, %{status: :completed, result: "done"}} = result

      GenServer.stop(pid)
    end

    test "returns failed status when agent fails", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: AwaitAgent, id: "await-fail", jido: jido)

      signal = Signal.new!("fail", %{}, source: "/test")
      AgentServer.cast(pid, signal)

      result = Await.completion(pid, 1000)
      assert {:ok, %{status: :failed}} = result

      GenServer.stop(pid)
    end

    test "returns timeout error when agent doesn't complete in time", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: AwaitAgent, id: "await-timeout", jido: jido)

      result = Await.completion(pid, 50)
      assert {:error, {:timeout, _details}} = result

      GenServer.stop(pid)
    end
  end

  describe "alive?/1" do
    test "returns true for alive agent", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: AwaitAgent, id: "alive-test", jido: jido)

      assert Await.alive?(pid) == true

      GenServer.stop(pid)
    end

    test "returns false for dead process" do
      fake_pid = spawn(fn -> :ok end)

      eventually(fn -> not Process.alive?(fake_pid) end)

      assert Await.alive?(fake_pid) == false
    end
  end

  describe "cancel/2" do
    test "sends cancel signal to agent", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: AwaitAgent, id: "cancel-test", jido: jido)

      assert :ok = Await.cancel(pid)
      assert :ok = Await.cancel(pid, reason: :user_cancelled)

      GenServer.stop(pid)
    end
  end

  describe "all/3" do
    test "returns empty map for empty list" do
      assert {:ok, %{}} = Await.all([])
    end

    test "waits for all agents to complete", %{jido: jido} do
      {:ok, pid1} = AgentServer.start_link(agent: AwaitAgent, id: "await-all-1", jido: jido)
      {:ok, pid2} = AgentServer.start_link(agent: AwaitAgent, id: "await-all-2", jido: jido)

      signal = Signal.new!("complete", %{}, source: "/test")
      AgentServer.cast(pid1, signal)
      AgentServer.cast(pid2, signal)

      result = Await.all([pid1, pid2], 2000)
      assert {:ok, results} = result
      assert map_size(results) == 2
      assert results[pid1].status == :completed
      assert results[pid2].status == :completed

      GenServer.stop(pid1)
      GenServer.stop(pid2)
    end

    test "returns timeout when not all complete in time", %{jido: jido} do
      {:ok, pid1} =
        AgentServer.start_link(agent: AwaitAgent, id: "await-all-timeout-1", jido: jido)

      {:ok, pid2} =
        AgentServer.start_link(agent: AwaitAgent, id: "await-all-timeout-2", jido: jido)

      signal = Signal.new!("complete", %{}, source: "/test")
      AgentServer.cast(pid1, signal)

      result = Await.all([pid1, pid2], 100)
      assert {:error, :timeout} = result

      GenServer.stop(pid1)
      GenServer.stop(pid2)
    end
  end

  describe "any/3" do
    test "returns timeout for empty list" do
      assert {:error, :timeout} = Await.any([])
    end

    test "returns first agent to complete", %{jido: jido} do
      {:ok, pid1} = AgentServer.start_link(agent: AwaitAgent, id: "await-any-1", jido: jido)
      {:ok, pid2} = AgentServer.start_link(agent: AwaitAgent, id: "await-any-2", jido: jido)

      signal = Signal.new!("complete", %{}, source: "/test")
      AgentServer.cast(pid1, signal)

      result = Await.any([pid1, pid2], 2000)
      assert {:ok, {winner_pid, completion}} = result
      assert winner_pid == pid1
      assert completion.status == :completed

      GenServer.stop(pid1)
      GenServer.stop(pid2)
    end

    test "returns timeout when none complete in time", %{jido: jido} do
      {:ok, pid1} =
        AgentServer.start_link(agent: AwaitAgent, id: "await-any-timeout-1", jido: jido)

      {:ok, pid2} =
        AgentServer.start_link(agent: AwaitAgent, id: "await-any-timeout-2", jido: jido)

      result = Await.any([pid1, pid2], 50)
      assert {:error, :timeout} = result

      GenServer.stop(pid1)
      GenServer.stop(pid2)
    end
  end

  describe "get_children/1" do
    test "returns empty map when no children", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: AwaitAgent, id: "children-empty", jido: jido)

      {:ok, children} = Await.get_children(pid)
      assert children == %{}

      GenServer.stop(pid)
    end

    test "exits for dead process" do
      fake_pid = spawn(fn -> :ok end)

      eventually(fn -> not Process.alive?(fake_pid) end)

      assert {:error, :not_found} = Await.get_children(fake_pid)
    end
  end

  describe "get_child/2" do
    test "returns error when child not found", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: AwaitAgent, id: "child-not-found", jido: jido)

      assert {:error, :child_not_found} = Await.get_child(pid, :nonexistent)

      GenServer.stop(pid)
    end

    test "exits for dead process" do
      fake_pid = spawn(fn -> :ok end)

      eventually(fn -> not Process.alive?(fake_pid) end)

      assert {:error, :not_found} = Await.get_child(fake_pid, :some_tag)
    end
  end

  describe "child/4" do
    test "returns timeout when child not found in time", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: AwaitAgent, id: "child-timeout", jido: jido)

      result = Await.child(pid, :nonexistent, 100)
      assert {:error, :timeout} = result

      GenServer.stop(pid)
    end
  end
end
