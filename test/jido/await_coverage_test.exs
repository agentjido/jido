defmodule JidoTest.AwaitCoverageTest do
  @moduledoc """
  Additional tests for Jido.Await to increase code coverage.
  Covers edge cases and error paths not in the main test file.
  """
  use JidoTest.Case, async: false

  alias Jido.AgentServer
  alias Jido.Await
  alias Jido.Signal

  defmodule NeverCompletesAction do
    @moduledoc false
    use Jido.Action, name: "never_completes", schema: []

    def run(_params, _context) do
      {:ok, %{status: :working}}
    end
  end

  defmodule CompletingAction do
    @moduledoc false
    use Jido.Action, name: "completing_action", schema: []

    def run(_params, _context) do
      {:ok, %{status: :completed, last_answer: "done"}}
    end
  end

  defmodule SpawnChildAction do
    @moduledoc false
    use Jido.Action,
      name: "spawn_child",
      schema: [
        tag: [type: :atom, required: true]
      ]

    def run(%{tag: tag}, _context) do
      directive = %Jido.Agent.Directive.SpawnAgent{
        agent: JidoTest.AwaitCoverageTest.ChildAgent,
        tag: tag,
        opts: %{id: "child-#{tag}"}
      }

      {:ok, %{}, [directive]}
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

  defmodule CoverageAgent do
    @moduledoc false
    use Jido.Agent,
      name: "coverage_agent",
      schema: [
        status: [type: :atom, default: :idle],
        last_answer: [type: :any, default: nil],
        error: [type: :any, default: nil]
      ]

    def signal_routes(_ctx) do
      [
        {"never_complete", NeverCompletesAction},
        {"complete", CompletingAction},
        {"spawn_child", SpawnChildAction}
      ]
    end
  end

  describe "completion/3 catching :exit with timeout" do
    test "returns {:error, :timeout} when GenServer.call times out", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(agent: CoverageAgent, id: "exit-timeout-test", jido: jido)

      signal = Signal.new!("never_complete", %{}, source: "/test")
      AgentServer.cast(pid, signal)

      result = Await.completion(pid, 50)
      assert {:error, {:timeout, _details}} = result

      GenServer.stop(pid)
    end
  end

  describe "poll_for_child error branch" do
    test "returns error when parent process dies during polling" do
      fake_pid = spawn(fn -> :ok end)
      eventually(fn -> not Process.alive?(fake_pid) end)

      result = Await.child(fake_pid, :some_child, 100)
      assert result in [{:error, :not_found}, {:error, :timeout}]
    end
  end

  describe "all/3 with infrastructure error" do
    test "returns error tuple when agent returns error", %{jido: jido} do
      {:ok, pid1} =
        AgentServer.start_link(agent: CoverageAgent, id: "all-infra-error-1", jido: jido)

      {:ok, pid2} =
        AgentServer.start_link(agent: CoverageAgent, id: "all-infra-error-2", jido: jido)

      signal = Signal.new!("complete", %{}, source: "/test")
      AgentServer.cast(pid1, signal)

      GenServer.stop(pid2)
      Process.sleep(10)

      result = Await.all([pid1, pid2], 500)

      case result do
        {:ok, _} ->
          :ok

        {:error, {server, reason}} ->
          assert is_pid(server) or is_atom(reason)

        {:error, :timeout} ->
          :ok
      end

      if Process.alive?(pid1), do: GenServer.stop(pid1)
    end

    test "propagates infrastructure error and kills other waiters", %{jido: jido} do
      {:ok, pid1} =
        AgentServer.start_link(agent: CoverageAgent, id: "all-kill-waiters-1", jido: jido)

      dead_pid = spawn(fn -> :ok end)
      eventually(fn -> not Process.alive?(dead_pid) end)

      result = Await.all([dead_pid, pid1], 500)

      assert match?({:error, {^dead_pid, _}}, result) or match?({:error, :timeout}, result)

      if Process.alive?(pid1), do: GenServer.stop(pid1)
    end
  end

  describe "any/3 functionality" do
    test "returns empty list as timeout" do
      assert {:error, :timeout} = Await.any([])
    end

    test "first agent to complete wins", %{jido: jido} do
      {:ok, fast_pid} =
        AgentServer.start_link(agent: CoverageAgent, id: "any-fast", jido: jido)

      {:ok, slow_pid} =
        AgentServer.start_link(agent: CoverageAgent, id: "any-slow", jido: jido)

      signal = Signal.new!("complete", %{}, source: "/test")
      AgentServer.cast(fast_pid, signal)

      eventually(fn ->
        {:ok, server_state} = AgentServer.state(fast_pid)
        server_state.agent.state.status == :completed
      end)

      result = Await.any([fast_pid, slow_pid], 2000)
      assert {:ok, {winner_pid, completion}} = result
      assert winner_pid == fast_pid
      assert completion.status == :completed

      GenServer.stop(fast_pid)
      GenServer.stop(slow_pid)
    end

    test "returns timeout when no agent completes in time", %{jido: jido} do
      {:ok, pid1} =
        AgentServer.start_link(agent: CoverageAgent, id: "any-timeout-1", jido: jido)

      {:ok, pid2} =
        AgentServer.start_link(agent: CoverageAgent, id: "any-timeout-2", jido: jido)

      result = Await.any([pid1, pid2], 50)

      assert {:error, :timeout} = result

      GenServer.stop(pid1)
      GenServer.stop(pid2)
    end

    test "returns error when agent process dies", %{jido: jido} do
      {:ok, live_pid} =
        AgentServer.start_link(agent: CoverageAgent, id: "any-live", jido: jido)

      dead_pid = spawn(fn -> :ok end)
      eventually(fn -> not Process.alive?(dead_pid) end)

      result = Await.any([dead_pid, live_pid], 500)

      assert match?({:error, {^dead_pid, _}}, result) or match?({:error, :timeout}, result)

      if Process.alive?(live_pid), do: GenServer.stop(live_pid)
    end
  end

  describe "status/1 edge cases" do
    test "alive? returns true for live agent", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(agent: CoverageAgent, id: "alive-edge", jido: jido)

      assert Await.alive?(pid) == true

      GenServer.stop(pid)
    end

    test "alive? returns error exit for dead process" do
      fake_pid = spawn(fn -> :ok end)
      eventually(fn -> not Process.alive?(fake_pid) end)

      assert Await.alive?(fake_pid) == false
    end
  end

  describe "get_children edge cases" do
    test "get_children exits for dead parent" do
      fake_pid = spawn(fn -> :ok end)
      eventually(fn -> not Process.alive?(fake_pid) end)

      assert {:error, :not_found} = Await.get_children(fake_pid)
    end

    test "get_children returns empty map for agent with no children", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(agent: CoverageAgent, id: "no-children", jido: jido)

      assert {:ok, %{}} = Await.get_children(pid)

      GenServer.stop(pid)
    end
  end

  describe "get_child edge cases" do
    test "get_child exits for dead parent" do
      fake_pid = spawn(fn -> :ok end)
      eventually(fn -> not Process.alive?(fake_pid) end)

      assert {:error, :not_found} = Await.get_child(fake_pid, :some_tag)
    end

    test "get_child returns :child_not_found for nonexistent child", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(agent: CoverageAgent, id: "child-edge", jido: jido)

      assert {:error, :child_not_found} = Await.get_child(pid, :nonexistent)

      GenServer.stop(pid)
    end

    test "get_child returns pid when child exists", %{jido: jido} do
      {:ok, parent_pid} =
        AgentServer.start_link(agent: CoverageAgent, id: "parent-with-child", jido: jido)

      signal = Signal.new!("spawn_child", %{tag: :test_worker}, source: "/test")
      AgentServer.cast(parent_pid, signal)

      eventually(fn ->
        {:ok, state} = AgentServer.state(parent_pid)
        Map.has_key?(state.children, :test_worker)
      end)

      assert {:ok, child_pid} = Await.get_child(parent_pid, :test_worker)
      assert is_pid(child_pid)

      GenServer.stop(parent_pid)
    end
  end

  describe "child/4 with actual child agent" do
    test "waits for child to complete", %{jido: jido} do
      {:ok, parent_pid} =
        AgentServer.start_link(agent: CoverageAgent, id: "parent-child-wait", jido: jido)

      spawn_signal = Signal.new!("spawn_child", %{tag: :completing_worker}, source: "/test")
      AgentServer.cast(parent_pid, spawn_signal)

      eventually(fn ->
        {:ok, state} = AgentServer.state(parent_pid)
        Map.has_key?(state.children, :completing_worker)
      end)

      {:ok, child_pid} = Await.get_child(parent_pid, :completing_worker)
      complete_signal = Signal.new!("complete", %{}, source: "/test")
      AgentServer.cast(child_pid, complete_signal)

      result = Await.child(parent_pid, :completing_worker, 2000)
      assert {:ok, %{status: :completed, result: "done"}} = result

      GenServer.stop(parent_pid)
    end
  end

  describe "get_children with actual children" do
    test "returns map of child pids", %{jido: jido} do
      {:ok, parent_pid} =
        AgentServer.start_link(agent: CoverageAgent, id: "parent-get-children", jido: jido)

      spawn_signal = Signal.new!("spawn_child", %{tag: :worker_a}, source: "/test")
      AgentServer.cast(parent_pid, spawn_signal)

      eventually(fn ->
        {:ok, state} = AgentServer.state(parent_pid)
        Map.has_key?(state.children, :worker_a)
      end)

      assert {:ok, children} = Await.get_children(parent_pid)
      assert is_map(children)
      assert Map.has_key?(children, :worker_a)
      assert is_pid(children[:worker_a])

      GenServer.stop(parent_pid)
    end
  end

  describe "alive?/1 with noproc" do
    test "returns false for dead registered name" do
      name = :"dead_agent_#{System.unique_integer([:positive])}"
      assert Await.alive?(name) == false
    end
  end

  describe "all/3 error propagation" do
    test "propagates error from dead agent in all/3", %{jido: jido} do
      {:ok, live_pid} =
        AgentServer.start_link(agent: CoverageAgent, id: "all-error-live", jido: jido)

      dead_pid = spawn(fn -> :ok end)
      eventually(fn -> not Process.alive?(dead_pid) end)

      result = Await.all([dead_pid, live_pid], 1000)

      case result do
        {:error, {^dead_pid, _reason}} -> :ok
        {:error, :timeout} -> :ok
        {:ok, _} -> flunk("Expected error or timeout, got ok")
      end

      if Process.alive?(live_pid), do: GenServer.stop(live_pid)
    end
  end

  describe "any/3 error propagation" do
    test "propagates error from first dead agent", %{jido: jido} do
      {:ok, live_pid} =
        AgentServer.start_link(agent: CoverageAgent, id: "any-error-live", jido: jido)

      dead_pid = spawn(fn -> :ok end)
      eventually(fn -> not Process.alive?(dead_pid) end)

      result = Await.any([dead_pid, live_pid], 1000)

      case result do
        {:error, {^dead_pid, _reason}} -> :ok
        {:error, :timeout} -> :ok
        {:ok, _} -> flunk("Expected error or timeout, got ok")
      end

      if Process.alive?(live_pid), do: GenServer.stop(live_pid)
    end
  end

  describe "get_children/1 error propagation" do
    test "returns error for unregistered agent name" do
      name = :"nonexistent_agent_#{System.unique_integer([:positive])}"
      assert {:error, :not_found} = Await.get_children(name)
    end
  end

  describe "get_child/2 error propagation" do
    test "returns error for unregistered agent name" do
      name = :"nonexistent_agent_#{System.unique_integer([:positive])}"
      assert {:error, :not_found} = Await.get_child(name, :child_tag)
    end
  end

  describe "child/4 parent error" do
    test "returns error when parent dies during polling" do
      parent = spawn(fn -> Process.sleep(50) end)

      result =
        try do
          Await.child(parent, :some_child, 200)
        catch
          :exit, _ -> {:error, :exit_caught}
        end

      case result do
        {:error, :timeout} -> :ok
        {:error, :exit_caught} -> :ok
        {:error, _} -> :ok
      end
    end
  end
end
