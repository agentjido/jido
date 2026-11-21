defmodule Jido.BehaviorTree.AgentTest do
  use ExUnit.Case, async: true

  alias Jido.BehaviorTree.{Agent, Tree, Blackboard}
  alias Jido.Joi
  alias Jido.BehaviorTree.Nodes.{Action, SetBlackboard}
  alias Jido.BehaviorTree.Test.Nodes.{SimpleNode, RunningNode, FailureNode}

  defmodule RuntimeStateAction do
    use Jido.Action,
      name: "runtime_state_action",
      description: "Mutates Jido agent state and emits a directive"

    @impl true
    def run(_params, _context) do
      signal = Jido.Signal.new!("jido.bt.test", %{ok: true}, source: "/bt/test")

      {:ok, %{status: :effect_applied}, [Jido.Agent.Directive.emit(signal)]}
    end
  end

  defmodule RuntimeContextAgent do
    use Jido.Agent, name: "bt_runtime_context_agent"

    state do
      schema Joi.object(%{status: Joi.atom() |> Joi.default(:idle)})
    end
  end

  describe "Agent.start_link/1" do
    test "starts agent with simple tree" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      {:ok, agent} = Agent.start_link(tree: tree)

      assert is_pid(agent)
      assert Process.alive?(agent)

      GenServer.stop(agent)
    end

    test "starts agent with initial blackboard" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      {:ok, agent} =
        Agent.start_link(
          tree: tree,
          blackboard: %{user_id: 123, status: "active"}
        )

      bb = Agent.blackboard(agent)
      assert Blackboard.get(bb, :user_id) == 123
      assert Blackboard.get(bb, :status) == "active"

      GenServer.stop(agent)
    end

    test "starts agent in manual mode by default" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      {:ok, agent} = Agent.start_link(tree: tree)

      assert Agent.mode(agent) == :manual

      GenServer.stop(agent)
    end

    test "starts agent in auto mode when specified" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      {:ok, agent} =
        Agent.start_link(
          tree: tree,
          mode: :auto,
          interval: 100
        )

      assert Agent.mode(agent) == :auto

      GenServer.stop(agent)
    end

    test "returns validation error when :tree is missing" do
      assert {:error, %Jido.BehaviorTree.Error.BehaviorTreeError{} = error} = Agent.start_link([])
      assert error.class == :invalid
      assert error.message =~ "Missing required :tree option"
    end

    test "returns validation error for invalid mode" do
      tree = Tree.new(SimpleNode.new("test"))

      assert {:error, %Jido.BehaviorTree.Error.BehaviorTreeError{} = error} =
               Agent.start_link(tree: tree, mode: :invalid)

      assert error.class == :invalid
      assert error.details.mode == :invalid
    end

    test "returns validation error for invalid interval" do
      tree = Tree.new(SimpleNode.new("test"))

      assert {:error, %Jido.BehaviorTree.Error.BehaviorTreeError{} = error} =
               Agent.start_link(tree: tree, interval: -1)

      assert error.class == :invalid
      assert error.details.interval == -1
    end

    test "returns validation error for non-map blackboard" do
      tree = Tree.new(SimpleNode.new("test"))

      assert {:error, %Jido.BehaviorTree.Error.BehaviorTreeError{} = error} =
               Agent.start_link(tree: tree, blackboard: :not_a_map)

      assert error.class == :invalid
      assert error.details.blackboard == :not_a_map
    end

    test "returns validation error for non-agent jido_agent option" do
      tree = Tree.new(SimpleNode.new("test"))

      assert {:error, %Jido.BehaviorTree.Error.BehaviorTreeError{} = error} =
               Agent.start_link(tree: tree, jido_agent: :invalid)

      assert error.class == :invalid
      assert error.details.jido_agent == :invalid
    end
  end

  describe "Agent.tick/1" do
    test "executes tree tick and returns status" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      {:ok, agent} = Agent.start_link(tree: tree)

      status = Agent.tick(agent)
      assert status == :success

      GenServer.stop(agent)
    end

    test "updates node state on tick" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      {:ok, agent} = Agent.start_link(tree: tree)

      # First tick
      Agent.tick(agent)

      # Second tick should increment tick count
      Agent.tick(agent)

      GenServer.stop(agent)
    end

    test "handles running nodes" do
      # Will run for 2 ticks
      node = RunningNode.new(2)
      tree = Tree.new(node)

      {:ok, agent} = Agent.start_link(tree: tree)

      # First tick should return :running
      status1 = Agent.tick(agent)
      assert status1 == :running

      # Second tick should return :success
      status2 = Agent.tick(agent)
      assert status2 == :success

      GenServer.stop(agent)
    end

    test "handles failing nodes" do
      node = FailureNode.new("test failure")
      tree = Tree.new(node)

      {:ok, agent} = Agent.start_link(tree: tree)

      status = Agent.tick(agent)
      assert status == :failure

      GenServer.stop(agent)
    end

    test "persists blackboard writes from SetBlackboard node" do
      tree = Tree.new(SetBlackboard.new(:status, :ready))
      {:ok, agent} = Agent.start_link(tree: tree)

      assert :success = Agent.tick(agent)
      assert :ready == Agent.get(agent, :status)

      GenServer.stop(agent)
    end

    test "merges Action results and captures directives when jido_agent is configured" do
      jido_agent = RuntimeContextAgent.instantiate!(id: "bt-runtime-test")
      tree = Tree.new(Action.new(RuntimeStateAction))

      {:ok, agent} = Agent.start_link(tree: tree, jido_agent: jido_agent)

      assert :success = Agent.tick(agent)

      updated_jido_agent = Agent.jido_agent(agent)
      assert %Jido.Agent{} = updated_jido_agent
      assert updated_jido_agent.state.status == :effect_applied
      assert Agent.get(agent, :last_result) == %{status: :effect_applied}

      directives = Agent.directives(agent)
      assert length(directives) == 1
      assert match?([%Jido.Agent.Directive.Emit{}], directives)

      GenServer.stop(agent)
    end
  end

  describe "Agent.status/1" do
    test "returns idle before first tick and latest status after ticking" do
      tree = Tree.new(SimpleNode.new("status"))
      {:ok, agent} = Agent.start_link(tree: tree)

      assert :idle == Agent.status(agent)
      assert :success == Agent.tick(agent)
      assert :success == Agent.status(agent)

      GenServer.stop(agent)
    end
  end

  describe "Agent.jido_agent/1 and Agent.directives/1" do
    test "returns nil agent context and empty directives before first tick by default" do
      tree = Tree.new(SimpleNode.new("defaults"))
      {:ok, agent} = Agent.start_link(tree: tree)

      assert Agent.jido_agent(agent) == nil
      assert Agent.directives(agent) == []

      GenServer.stop(agent)
    end
  end

  describe "Agent.blackboard/1" do
    test "returns current blackboard" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      {:ok, agent} =
        Agent.start_link(
          tree: tree,
          blackboard: %{initial: "data"}
        )

      bb = Agent.blackboard(agent)
      assert Blackboard.get(bb, :initial) == "data"

      GenServer.stop(agent)
    end
  end

  describe "Agent.put/3 and Agent.get/3" do
    test "stores and retrieves values from blackboard" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      {:ok, agent} = Agent.start_link(tree: tree)

      :ok = Agent.put(agent, :key, "value")
      value = Agent.get(agent, :key)
      assert value == "value"

      GenServer.stop(agent)
    end

    test "returns default for missing keys" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      {:ok, agent} = Agent.start_link(tree: tree)

      value = Agent.get(agent, :missing_key, "default")
      assert value == "default"

      GenServer.stop(agent)
    end
  end

  describe "Agent.replace_root/2" do
    test "replaces the root node of the tree" do
      old_node = SimpleNode.new("old")
      tree = Tree.new(old_node)

      {:ok, agent} = Agent.start_link(tree: tree)

      new_node = SimpleNode.new("new")
      :ok = Agent.replace_root(agent, new_node)

      # Verify the tree was updated by checking tick behavior
      Agent.tick(agent)

      GenServer.stop(agent)
    end
  end

  describe "Agent.halt/1" do
    test "halts the agent and cleans up tree" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      {:ok, agent} = Agent.start_link(tree: tree)

      :ok = Agent.halt(agent)

      GenServer.stop(agent)
    end
  end

  describe "Agent.set_mode/2" do
    test "changes from manual to auto mode" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      {:ok, agent} = Agent.start_link(tree: tree, mode: :manual)

      assert Agent.mode(agent) == :manual

      :ok = Agent.set_mode(agent, :auto)
      assert Agent.mode(agent) == :auto

      GenServer.stop(agent)
    end

    test "changes from auto to manual mode" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      {:ok, agent} =
        Agent.start_link(
          tree: tree,
          mode: :auto,
          interval: 100
        )

      assert Agent.mode(agent) == :auto

      :ok = Agent.set_mode(agent, :manual)
      assert Agent.mode(agent) == :manual

      GenServer.stop(agent)
    end

    test "returns validation error for invalid mode and keeps existing mode" do
      tree = Tree.new(SimpleNode.new("test"))
      {:ok, agent} = Agent.start_link(tree: tree, mode: :manual)

      assert {:error, %Jido.BehaviorTree.Error.BehaviorTreeError{} = error} =
               Agent.set_mode(agent, :invalid)

      assert error.class == :invalid
      assert Agent.mode(agent) == :manual

      GenServer.stop(agent)
    end
  end

  describe "Auto mode execution" do
    test "automatically ticks in auto mode" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      {:ok, agent} =
        Agent.start_link(
          tree: tree,
          mode: :auto,
          # Short interval for testing
          interval: 50
        )

      # Wait for a few automatic ticks
      Process.sleep(150)

      GenServer.stop(agent)
    end

    test "ignores internal :tick messages when in manual mode" do
      tree = Tree.new(SimpleNode.new("test"))
      {:ok, agent} = Agent.start_link(tree: tree, mode: :manual)

      send(agent, :tick)
      Process.sleep(20)

      assert Agent.status(agent) == :idle

      GenServer.stop(agent)
    end
  end

  describe "Agent termination" do
    test "properly cleans up on termination" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      {:ok, agent} = Agent.start_link(tree: tree)

      # Monitor the process
      monitor_ref = Process.monitor(agent)

      # Stop the agent
      GenServer.stop(agent)

      # Wait for termination
      receive do
        {:DOWN, ^monitor_ref, :process, ^agent, _reason} ->
          :ok
      after
        1000 ->
          flunk("Agent did not terminate within timeout")
      end
    end
  end
end
